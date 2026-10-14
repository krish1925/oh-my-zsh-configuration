"""sandbox — isolated code execution for the ?? agent: no network, no access to
the real filesystem, no state carried between calls. This exists to fix a
genuine failure mode of small models: they hand-compute arithmetic, sequences
or data transforms "from memory" and get large numbers wrong (verified: this
9B model gave a wildly incorrect 40th-50th Fibonacci number when asked to
"run" a script it never actually ran). Point it at run_python instead of
letting it guess.

Isolation (verified empirically on macOS 15.7.8 / Apple Silicon M4 Pro):
  - Docker, ONLY if the daemon is already running (never started by this
    tool — starting Docker Desktop's Linux VM costs real RAM, and this
    machine runs close to its ceiling; start it yourself for this tier):
    --network none, --read-only rootfs + a small tmpfs, no bind mounts to
    the host at all (code goes in over stdin), --memory/--pids-limit, --rm.
  - Otherwise (the default, always available): macOS Seatbelt
    (`sandbox-exec`) with a profile that:
      * (deny network*) — verified inherited by every child process, even
        one that execs a real network tool like curl from inside
      * allows read+write ONLY inside a fresh scratch directory (a fresh
        tempfile.mkdtemp() per call, deleted immediately after); read-only
        access to the system paths a Python/shell process needs to start
      * process-exec allowed under /bin, /usr/bin, /opt/homebrew — still
        safe, because sandbox restrictions are inherited by every child
        process (verified: subprocess.run(['/opt/homebrew/bin/python3', …])
        from inside the sandbox is itself still network- and fs-denied)
  Both paths: a wall-clock timeout (the process is killed if it runs long),
  a RLIMIT_CPU backstop (macOS does not support RLIMIT_AS/RLIMIT_DATA
  reduction — verified — so CPU time is the only rlimit that actually
  enforces here), and output capture bounded to MAX_OUTPUT_BYTES so a
  print-bomb can't exhaust the AGENT's memory while collecting output (we
  read with a byte cap via Popen pipes, not subprocess.run(capture_output=
  True), which would buffer everything before we get a chance to truncate).

Known limitation, stated plainly: this stops the sandbox itself from
exfiltrating anything (no network reaches it) and stops it touching the real
disk. It does NOT stop the model from later trying to smuggle sandboxed
OUTPUT out through a different, non-sandboxed tool (web_search / fetch_url) —
that is guard.py's job, and its leak-check is a literal substring match that
will not catch deliberately obfuscated (base64/hex/rot13) data. Sandbox
output is quarantined here as `kind: "sandbox"` (see mcp.json), which the
agent treats like `private`: remembered so it cannot leave, but any actual
transform is on the model to attempt and the leak-check to catch in its
plain form only. This is the same fundamental limit the rest of this
codebase's leak-check already has; it is not new here.
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import time

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

mcp = MCPServer("sandbox", instructions="Run small Python or shell scripts in a throwaway, network-free sandbox — "
                                        "no access to real files, nothing persists. Use for arithmetic, sequences, "
                                        "data transforms or verifying a snippet actually works, instead of computing "
                                        "it from memory (small models get multi-digit arithmetic wrong).")
# Not readOnlyHint: it executes code. It is exposed anyway via mcp.json's per-tool
# "tools" override (see Tools.load in agent.py) — the isolation itself is the
# safety property here, not "did this change anything the user's session sees".
ANN = ToolAnnotations(readOnlyHint=False, destructiveHint=False, openWorldHint=False)

MAX_OUTPUT_BYTES = 64_000
DEFAULT_TIMEOUT = 10.0
MAX_TIMEOUT = 30.0


def _find_python() -> str:
    """NOT shutil.which(): this whole agent runs via `uv run --script`, whose
    PEP 723 machinery puts an ephemeral build directory's own `python3` FIRST
    on PATH (e.g. ~/.cache/uv/builds-v0/.tmpXXXX/bin/python3) — shutil.which
    would resolve to that, which is outside every allowed process-exec path
    below and fails with a silent "Operation not permitted". Verified by
    testing: this exact bug made run_python unusable end-to-end until fixed."""
    for candidate in ("/opt/homebrew/bin/python3", "/usr/bin/python3", "/usr/local/bin/python3"):
        if os.path.exists(candidate):
            return candidate
    return "/usr/bin/python3"   # macOS always ships this


PY = _find_python()
# A clean, minimal PATH for anything spawned INSIDE the sandbox (a run_shell
# script invoking `python3` by bare name hits the exact same PATH-pollution
# problem otherwise). Also strips secrets/config (ZAH_KEY, HF_HOME, etc.) that
# this MCP server's own process happens to have inherited — the sandboxed
# script doesn't need any of that and shouldn't see it.
SANDBOX_ENV = {"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
               "LANG": "en_US.UTF-8", "TERM": "dumb"}


# ---------------------------------------------------------------- Seatbelt
def _resolve(p: str) -> str:
    return os.path.realpath(p)   # /tmp -> /private/tmp: the sandbox checks the RESOLVED path


def _profile(scratch: str) -> str:
    scratch = _resolve(scratch)
    read_paths = ["/usr/lib", "/usr/bin", "/bin", "/System/Library", "/private/etc", "/dev",
                  "/opt/homebrew", "/private/var/db/dyld", "/Library/Preferences"]
    reads = " ".join(f'(subpath "{p}")' for p in read_paths)
    return f'''(version 1)
(deny default)
(allow process-fork)
(allow process-exec (subpath "/bin") (subpath "/usr/bin") (subpath "/opt/homebrew"))
(allow signal (target self))
(allow sysctl-read)
(allow mach-lookup)
(allow file-read-metadata)
(allow file-read-data (literal "/"))
(allow file-read* {reads})
(allow file-read* file-write* (subpath "{scratch}"))
(allow file-write-data (literal "/dev/null") (literal "/dev/dtracehelper"))
(deny network*)
'''


def _limit_cpu():   # preexec_fn: CPU-time backstop if the wall-clock timeout somehow doesn't fire
    import resource
    try:
        resource.setrlimit(resource.RLIMIT_CPU, (int(MAX_TIMEOUT) + 5, int(MAX_TIMEOUT) + 5))
    except (ValueError, OSError):
        pass


def _kill_tree(proc: subprocess.Popen):
    try:
        os.killpg(os.getpgid(proc.pid), 9)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            proc.kill()
        except OSError:
            pass
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass


def _run_bounded(argv: list[str], cwd: str, timeout: float) -> tuple[str, int, bool]:
    """Run argv, capture up to MAX_OUTPUT_BYTES combined, kill on timeout.
    Returns (output, returncode, timed_out).

    Uses select() on the pipe, NOT a blocking os.read(): a process that
    produces zero output (e.g. `while True: time.sleep(1)`) would otherwise
    block the read forever and the deadline check below it would never run —
    this was a real bug caught by testing (the timeout silently didn't fire
    for output-free infinite loops). select() with a timeout is what lets the
    deadline actually get checked even when nothing is coming down the pipe.
    """
    import select
    env = {**SANDBOX_ENV, "HOME": cwd, "TMPDIR": cwd}
    proc = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL, preexec_fn=_limit_cpu, start_new_session=True, env=env)
    fd = proc.stdout.fileno()
    out_parts: list[bytes] = []
    total = 0
    deadline = time.monotonic() + timeout
    timed_out = False
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            timed_out = True
            break
        ready, _, _ = select.select([fd], [], [], min(remaining, 0.5))
        if not ready:
            continue   # nothing yet — loop back and re-check the deadline
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:   # EOF: process closed its output (usually means it exited)
            break
        out_parts.append(chunk)
        total += len(chunk)
        if total >= MAX_OUTPUT_BYTES:
            break
    if timed_out or total >= MAX_OUTPUT_BYTES or proc.poll() is None:
        # give it a brief moment to exit on its own (EOF often precedes wait() by a hair),
        # then force-kill the whole process group so children can't outlive the parent
        try:
            rc = proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            _kill_tree(proc)
            rc = proc.returncode if proc.returncode is not None else -9
    else:
        rc = proc.wait()
    out = b"".join(out_parts).decode(errors="replace")
    if total >= MAX_OUTPUT_BYTES:
        out = out[:MAX_OUTPUT_BYTES] + "\n…[output truncated at 64KB]"
    return out, rc, timed_out


def _seatbelt_run(argv: list[str], code: str | None, timeout: float) -> str:
    scratch = tempfile.mkdtemp(prefix="zagent-sb-")
    try:
        os.chmod(scratch, stat.S_IRWXU)
        profile_path = os.path.join(scratch, ".profile.sb")
        with open(profile_path, "w") as f:
            f.write(_profile(scratch))
        full_argv = ["/usr/bin/sandbox-exec", "-f", profile_path, *argv]
        out, rc, timed_out = _run_bounded(full_argv, cwd=scratch, timeout=timeout)
        if timed_out:
            return (out + f"\n[killed: exceeded {timeout:.0f}s timeout — no state was saved, nothing outside the "
                           f"sandbox was touched]")
        return out if out else f"(no output, exit {rc})"
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


# ---------------------------------------------------------------- Docker (opportunistic)
def _docker_available() -> bool:
    try:
        r = subprocess.run(["docker", "info"], capture_output=True, timeout=2, stdin=subprocess.DEVNULL)
        return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired, FileNotFoundError):
        return False


def _docker_run(image: str, argv: list[str], code: str, timeout: float) -> str:
    import select
    import uuid
    name = f"zagent-sb-{uuid.uuid4().hex[:12]}"
    cmd = ["docker", "run", "--rm", "-i", "--name", name, "--network", "none", "--read-only",
           "--tmpfs", "/tmp:rw,size=64m,mode=1777", "--memory", "256m", "--pids-limit", "64",
           "--cpus", "1", "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
           "--user", "nobody", image, *argv]
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 start_new_session=True)
    except OSError as e:
        return f"(docker failed to start: {e})"
    try:
        proc.stdin.write(code.encode())
        proc.stdin.close()
    except (BrokenPipeError, OSError):
        pass
    fd = proc.stdout.fileno()
    out_parts: list[bytes] = []
    total = 0
    deadline = time.monotonic() + timeout
    timed_out = False
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            timed_out = True
            break
        ready, _, _ = select.select([fd], [], [], min(remaining, 0.5))
        if not ready:
            continue
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        out_parts.append(chunk)
        total += len(chunk)
        if total >= MAX_OUTPUT_BYTES:
            break
    if timed_out or total >= MAX_OUTPUT_BYTES or proc.poll() is None:
        try:
            proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            # killing the local `docker run` CLI process disconnects it but leaves the
            # container itself running server-side (--rm only fires on a clean exit) —
            # `docker kill` by the name we tagged it with reaps the actual container.
            subprocess.run(["docker", "kill", name], capture_output=True, timeout=5)
            _kill_tree(proc)
    out = b"".join(out_parts).decode(errors="replace")
    if total >= MAX_OUTPUT_BYTES:
        out = out[:MAX_OUTPUT_BYTES] + "\n…[output truncated at 64KB]"
    if timed_out:
        out += f"\n[killed: exceeded {timeout:.0f}s timeout]"
    return out if out else "(no output)"


def _clamp_timeout(t: float) -> float:
    try:
        t = float(t)
    except (TypeError, ValueError):
        t = DEFAULT_TIMEOUT
    return max(1.0, min(t, MAX_TIMEOUT))


@mcp.tool(annotations=ANN)
def run_python(code: str, timeout: float = DEFAULT_TIMEOUT) -> str:
    """Run a Python snippet in an isolated sandbox and return its stdout/stderr.
    No network, no access to your real files, nothing persists between calls —
    every call starts fresh. Use this for arithmetic, generating sequences,
    parsing/transforming data, or checking that code actually works, instead
    of computing or guessing the result yourself. timeout: seconds, max 30."""
    if not code or not code.strip():
        return "no code given"
    if len(code) > 20000:
        return "code too long (max 20000 chars)"
    timeout = _clamp_timeout(timeout)
    if _docker_available():
        return _docker_run("python:3.12-alpine", ["python3", "-u", "-c", "import sys; exec(sys.stdin.read())"], code, timeout)
    return _seatbelt_run([PY, "-I", "-c", code], code, timeout)


@mcp.tool(annotations=ANN)
def run_shell(script: str, timeout: float = DEFAULT_TIMEOUT) -> str:
    """Run a small POSIX shell script in an isolated sandbox and return its
    output. No network, no access to your real files, nothing persists.
    Good for quick file/text transforms on data you paste in, or checking a
    pipeline of commands actually does what you think. Basic tools only
    (the shell itself, coreutils); it cannot reach your actual filesystem or
    the internet. timeout: seconds, max 30."""
    if not script or not script.strip():
        return "no script given"
    if len(script) > 20000:
        return "script too long (max 20000 chars)"
    timeout = _clamp_timeout(timeout)
    if _docker_available():
        return _docker_run("alpine:3", ["sh"], script, timeout)
    return _seatbelt_run(["/bin/sh", "-c", script], script, timeout)


@mcp.tool(annotations=ANN)
def sandbox_status() -> str:
    """Which isolation backend is active right now (Docker or macOS Seatbelt)."""
    if _docker_available():
        return "docker (daemon running) — containers, --network none, --read-only rootfs, no host mounts"
    return "macos-seatbelt (sandbox-exec) — network denied, filesystem limited to a fresh scratch dir per call"


if __name__ == "__main__":
    mcp.run()
