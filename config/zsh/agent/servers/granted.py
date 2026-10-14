"""granted — read-only MCP server for directories OUTSIDE the current project that the
user has explicitly, and recently, agreed to let ?? browse (agent.py's
request_directory_access, gated by a real y/N read from /dev/tty — see dirgrants.py).

Every call here re-reads the grants file fresh and re-checks expiry — there is no cache,
no "was granted earlier this run" shortcut, so a grant that has expired (or was revoked
with `dirgrants.py revoke`) stops working on the VERY NEXT call, mid-conversation if need
be. This is deliberate: the enforcement point is "is there a live grant right now", never
"was there ever a grant." Model-supplied paths cannot widen this on their own — the only
way a NEW directory becomes readable is a fresh request_directory_access call, which means
a fresh human y/N in agent.py's process; nothing in this file can grant or extend access.

Same discipline as workspace.py: symlink resolution before the jail check, a secret-file
deny-list, and no writes of any kind.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))   # for dirgrants, which lives one level up (alongside agent.py)

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

import dirgrants
from _safety import DENY, SKIP_DIRS, redact

mcp = MCPServer("granted", instructions="Read-only access to OTHER directories the user has explicitly and "
                                        "recently approved (request_directory_access) — refuses everything else, "
                                        "including anything whose approval has expired.")
RO = ToolAnnotations(readOnlyHint=True, destructiveHint=False, openWorldHint=False)


class Refused(ValueError):
    pass


def safe(path: str) -> tuple[Path, Path]:
    """Resolve `path`, find which (if any) active grant covers it, and refuse anything
    that escapes that grant's root (symlinks included) or looks like a secret. Returns
    (resolved_path, grant_root)."""
    if not path or not path.strip():
        raise Refused("path is required — an absolute path, or one starting with ~")
    p = Path(path).expanduser()
    if not p.is_absolute():
        raise Refused("path must be absolute (or start with ~) — this server has no 'current directory' of its own")
    q = p.resolve()
    root = dirgrants.active_root_for(q)
    if root is None:
        raise Refused(f"no active access grant covers {q} — ask ?? to call request_directory_access on it first "
                       "(needs the user's explicit y/N); grants also expire after 7 days")
    try:
        rel = str(q.relative_to(root))
    except ValueError:
        raise Refused("outside the granted directory")
    if DENY.search(rel):
        raise Refused("secret-looking file — not readable through this tool")
    return q, root


def _safe(fn):
    import functools

    @functools.wraps(fn)
    def w(*a, **k):
        try:
            return fn(*a, **k)
        except Refused as e:
            return f"refused: {e}"
        except (OSError, subprocess.TimeoutExpired) as e:
            return f"error: {e.__class__.__name__}: {e}"
    return w


@mcp.tool(annotations=RO)
@_safe
def list_granted_dir(path: str, depth: int = 1) -> str:
    """List files/directories under `path` (an ABSOLUTE path, or one starting with ~ —
    this is for directories OUTSIDE the current project; use list_dir for the project
    itself). `path` must be inside a directory the user has already approved via
    request_directory_access — everything else is refused. depth: 1-3."""
    q, root = safe(path)
    depth = max(1, min(int(depth), 3))
    if not q.is_dir():
        return f"not a directory: {path}"
    out = []

    def walk(d: Path, level: int, prefix: str):
        try:
            entries = sorted(d.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
        except OSError:
            return
        for e in entries[:300]:
            if e.name in SKIP_DIRS or (e.name.startswith(".") and e.name not in (".github", ".gitignore")):
                continue
            rel = e.relative_to(root)
            if DENY.search(str(rel)):
                out.append(f"{prefix}{e.name} [hidden]")
                continue
            tag = "/" if e.is_dir() else ""
            out.append(f"{prefix}{e.name}{tag}")
            if e.is_dir() and level < depth:
                walk(e, level + 1, prefix + "  ")

    walk(q, 1, "")
    return f"{q}:\n" + "\n".join(out[:400]) if out else "(empty)"


@mcp.tool(annotations=RO)
@_safe
def read_granted_file(path: str, start_line: int = 1, max_lines: int = 200) -> str:
    """Read a text file inside a directory the user has already approved via
    request_directory_access. `path` is an ABSOLUTE path (or starts with ~). Starts at
    start_line, up to max_lines (default 200, max 200) or 16KB. Refuses binary files,
    anything outside the granted directory, or anything that looks like a secret."""
    q, root = safe(path)
    if not q.is_file():
        return f"not a file: {path}"
    if q.stat().st_size > 4_000_000:
        return "file too large to read (>4MB)"
    raw = q.read_bytes()[:8192]
    if b"\x00" in raw:
        return "binary file — not shown"
    max_lines = max(1, min(int(max_lines), 200))
    start_line = max(1, int(start_line))
    text = q.read_text(errors="replace")
    lines = text.splitlines()
    chunk = lines[start_line - 1: start_line - 1 + max_lines]
    body = "\n".join(f"{i + start_line:5d}| {l}" for i, l in enumerate(chunk))
    body = redact(body)
    if len(body) > 16000:
        body = body[:16000] + "\n…[truncated]"
    more = f"\n…({len(lines) - (start_line - 1 + len(chunk))} more lines)" if start_line - 1 + len(chunk) < len(lines) else ""
    return f"{q} (lines {start_line}-{start_line + len(chunk) - 1} of {len(lines)}):\n{body}{more}"


@mcp.tool(annotations=RO)
@_safe
def grep_granted_dir(path: str, pattern: str, glob: str = "", max_results: int = 50) -> str:
    """Search file contents for a regex `pattern` (ripgrep syntax) under `path` — an
    ABSOLUTE directory (or starting with ~) inside a directory the user has already
    approved via request_directory_access. Optionally restrict to files matching `glob`
    (e.g. "*.py"). Results are file:line:text, capped at max_results."""
    q, root = safe(path)
    if not q.is_dir():
        return f"not a directory: {path}"
    max_results = max(1, min(int(max_results), 200))
    argv = ["rg", "--no-config", "-n", "-S", "--max-count", "5", "--max-columns", "300"]
    if glob:
        argv += ["-g", glob]
    for d in SKIP_DIRS:
        argv += ["-g", f"!{d}"]
    argv += ["--", pattern, str(q)]      # `--` is load-bearing: pattern can never be parsed as a flag
    p = subprocess.run(argv, capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    if p.returncode not in (0, 1):
        return f"search error: {(p.stderr or 'unknown')[:300]}"
    lines = [l for l in (p.stdout or "").splitlines() if not DENY.search(l.split(":", 1)[0].replace(str(root) + "/", ""))]
    lines = lines[:max_results]
    if not lines:
        return f"no matches for {pattern!r}"
    return redact("\n".join(lines))


if __name__ == "__main__":
    mcp.run()
