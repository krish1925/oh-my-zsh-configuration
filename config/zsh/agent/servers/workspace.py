"""workspace — read-only MCP server: answer questions about the current repo.

Jailed to the git repository containing the directory ?? was started from (or
that directory itself, if it isn't a git repo). Every path is resolved and
checked against the jail AFTER symlink resolution, so a symlink pointing
outside the workspace, or a `../../` escape, is refused the same way. A
deny-list additionally blocks anything that looks like a secret file, even
inside the jail (a compromised or malicious repo could otherwise be used to
read its own `.env`, and the agent doesn't distinguish "your project" from
"an untrusted checkout you just cloned to look at").

Nothing here writes. `git status/log/diff` never mutate. `grep`/`fd` calls use
a fixed argv with `--` before the pattern, so a hostile "pattern" can never be
interpreted as a flag (this is how a malicious file NAME, not just content,
could otherwise smuggle `--pre=sh` into ripgrep and run arbitrary code).
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

from _safety import DENY, SKIP_DIRS, redact

mcp = MCPServer("workspace", instructions="Read-only access to the current project: files, search, git. Nothing outside it, nothing that writes.")
RO = ToolAnnotations(readOnlyHint=True, destructiveHint=False, openWorldHint=False)

# ---- the jail --------------------------------------------------------------
def _find_root() -> Path | None:
    start = Path(os.environ.get("ZAH_WORKSPACE", ".")).resolve()
    try:
        g = subprocess.run(["git", "-C", str(start), "rev-parse", "--show-toplevel"],
                            capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL)
        if g.returncode == 0 and g.stdout.strip():
            root = Path(g.stdout.strip()).resolve()
        else:
            root = start
    except (OSError, subprocess.TimeoutExpired):
        root = start
    # never let $HOME or / itself be the jail — that's not "a project", that's everything
    if root in (Path.home(), Path("/")):
        return None
    return root


ROOT = _find_root()


def _root_label() -> str:
    """Where the project actually is (~-relative), so the model never mistakes the
    project root "." for the user's home directory."""
    if ROOT is None:
        return "no project"
    home = str(Path.home())
    r = str(ROOT)
    return "~" + r[len(home):] if r.startswith(home) else r


class Jailed(ValueError):
    pass


def safe(rel: str) -> Path:
    """Resolve a path relative to ROOT, refusing anything outside it (symlinks
    included — resolve() follows them) or that looks like a secret."""
    if ROOT is None:
        raise Jailed("no workspace: cd into a project directory before asking ?? about code")
    rel = (rel or ".").strip()
    if rel.startswith(("~", "/")) or ".." in Path(rel).parts:
        raise Jailed(f"{rel!r} is outside this project ({_root_label()}). To look at another directory, call "
                     "request_directory_access with its path — it asks the user; then use list_granted_dir/"
                     "read_granted_file on it. Do not try run_shell for this: the sandbox has no real files.")
    q = (ROOT / rel).resolve()
    if q != ROOT and ROOT not in q.parents:
        raise Jailed("outside the workspace")
    try:
        relpath = str(q.relative_to(ROOT))
    except ValueError:
        raise Jailed("outside the workspace")
    if DENY.search(relpath):
        raise Jailed("secret-looking file — not readable through this tool")
    return q


def _safe(fn):
    import functools

    @functools.wraps(fn)
    def w(*a, **k):
        try:
            return fn(*a, **k)
        except Jailed as e:
            return f"refused: {e}"
        except (OSError, subprocess.TimeoutExpired) as e:
            return f"error: {e.__class__.__name__}: {e}"
    return w


def git(*args: str, timeout: float = 6) -> str:
    if ROOT is None:
        return "refused: no workspace"
    p = subprocess.run(["git", "-C", str(ROOT), "--no-pager", "-c", "core.pager=cat",
                        "-c", "core.editor=true", *args],
                        capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    return (p.stdout or p.stderr).strip()


@mcp.tool(annotations=RO)
@_safe
def list_dir(path: str = ".", depth: int = 1) -> str:
    """List files and directories under `path` — relative to the project root, e.g. "." or "src" (never an absolute path — the root is not /Users/... or /home/..., it is wherever this project lives; you don't know that path, so don't guess it), up to `depth` levels deep (1-3). Skips .git, node_modules, build output."""
    root = safe(path)
    depth = max(1, min(int(depth), 3))
    if not root.is_dir():
        return f"not a directory: {path}"
    out = []

    def walk(d: Path, level: int, prefix: str):
        try:
            entries = sorted(d.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
        except OSError:
            return
        for e in entries[:300]:
            if e.name in SKIP_DIRS or e.name.startswith(".") and e.name not in (".github", ".gitignore"):
                continue
            rel = e.relative_to(ROOT)
            if DENY.search(str(rel)):
                out.append(f"{prefix}{e.name} [hidden]")
                continue
            tag = "/" if e.is_dir() else ""
            out.append(f"{prefix}{e.name}{tag}")
            if e.is_dir() and level < depth:
                walk(e, level + 1, prefix + "  ")

    walk(root, 1, "")
    where = f"{root.relative_to(ROOT)}" if root != ROOT else f". (project root = {_root_label()} — NOT the home directory)"
    return f"{where}:\n" + "\n".join(out[:400]) if out else "(empty)"


@mcp.tool(annotations=RO)
@_safe
def read_file(path: str, start_line: int = 1, max_lines: int = 200) -> str:
    """Read a text file from the project. `path` is relative to the project root, e.g. "src/main.py" (never an absolute path — you don't know the real filesystem path of this project; use list_dir or find_files first if unsure of the name). Starts at start_line, up to max_lines (default 200, max 200) or 16KB, whichever comes first. Refuses binary files and anything outside the project or that looks like a secret."""
    p = safe(path)
    if not p.is_file():
        return f"not a file: {path}"
    if p.stat().st_size > 4_000_000:
        return "file too large to read (>4MB)"
    raw = p.read_bytes()[:8192]
    if b"\x00" in raw:
        return "binary file — not shown"
    max_lines = max(1, min(int(max_lines), 200))
    start_line = max(1, int(start_line))
    text = p.read_text(errors="replace")
    lines = text.splitlines()
    chunk = lines[start_line - 1: start_line - 1 + max_lines]
    body = "\n".join(f"{i + start_line:5d}| {l}" for i, l in enumerate(chunk))
    body = redact(body)
    if len(body) > 16000:
        body = body[:16000] + "\n…[truncated]"
    more = f"\n…({len(lines) - (start_line - 1 + len(chunk))} more lines)" if start_line - 1 + len(chunk) < len(lines) else ""
    return f"{p.relative_to(ROOT)} (lines {start_line}-{start_line + len(chunk) - 1} of {len(lines)}):\n{body}{more}"


@mcp.tool(annotations=RO)
@_safe
def grep(pattern: str, glob: str = "", max_results: int = 50) -> str:
    """Search file contents in the project for a regex pattern (ripgrep syntax). Takes only `pattern`, `glob` and `max_results` — there is no `path` argument; the whole project is always searched. Optionally restrict to files matching `glob` (e.g. "*.py"). Results are file:line:text, capped at max_results."""
    if ROOT is None:
        return "refused: no workspace"
    max_results = max(1, min(int(max_results), 200))
    argv = ["rg", "--no-config", "-n", "-S", "--max-count", "5", "--max-columns", "300"]
    if glob:
        argv += ["-g", glob]
    for d in SKIP_DIRS:
        argv += ["-g", f"!{d}"]
    argv += ["--", pattern, str(ROOT)]      # `--` is load-bearing: pattern can never be parsed as a flag
    p = subprocess.run(argv, capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL)
    if p.returncode not in (0, 1):
        return f"search error: {(p.stderr or 'unknown')[:300]}"
    lines = [l for l in (p.stdout or "").splitlines() if not DENY.search(l.split(":", 1)[0].replace(str(ROOT) + "/", ""))]
    lines = [l.replace(str(ROOT) + "/", "") for l in lines[:max_results]]
    if not lines:
        return f"no matches for {pattern!r}"
    return redact("\n".join(lines))


@mcp.tool(annotations=RO)
@_safe
def find_files(name_glob: str, max_results: int = 100) -> str:
    """Find files by name pattern (glob, e.g. "*.test.js" or "**/config*")."""
    if ROOT is None:
        return "refused: no workspace"
    max_results = max(1, min(int(max_results), 300))
    argv = ["fd", "--glob", "--hidden"]
    for d in SKIP_DIRS:
        argv += ["-E", d]
    argv += ["--max-results", str(max_results), "--", name_glob, str(ROOT)]
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=8, stdin=subprocess.DEVNULL)
        rows = (p.stdout or "").splitlines()
    except FileNotFoundError:
        rows = [str(x) for x in ROOT.rglob(name_glob) if not any(part in SKIP_DIRS for part in x.parts)][:max_results]
    rows = [r.replace(str(ROOT) + "/", "") for r in rows if not DENY.search(r.replace(str(ROOT) + "/", ""))]
    return "\n".join(rows[:max_results]) if rows else f"no files matching {name_glob!r}"


@mcp.tool(annotations=RO)
@_safe
def git_status() -> str:
    """git status for the project (short format)."""
    if ROOT is None:
        return "refused: no workspace"
    branch = git("branch", "--show-current")
    status = git("status", "--short")
    return f"branch: {branch or '(detached)'}\n" + (status or "(clean)")


@mcp.tool(annotations=RO)
@_safe
def git_log(n: int = 15) -> str:
    """Recent commit log (one line each)."""
    n = max(1, min(int(n), 100))
    return git("log", f"-{n}", "--oneline", "--decorate") or "(no commits)"


@mcp.tool(annotations=RO)
@_safe
def git_diff(path: str = "", staged: bool = False) -> str:
    """Diff of uncommitted changes (working tree, or --staged). `path`, if given, is relative to the project root, e.g. "src/main.py" (never an absolute path). Diff filters/textconv/pagers are disabled so a malicious repo's git config cannot run code through this."""
    if path:
        safe(path)   # validates it's inside the jail; git gets the relative path
    argv = ["diff", "--no-ext-diff", "--no-textconv", "--no-color"]
    if staged:
        argv.append("--staged")
    if path:
        argv += ["--", path]
    out = git(*argv, timeout=10)
    out = redact(out)
    return out[:20000] + ("\n…[truncated]" if len(out) > 20000 else "") if out else "(no changes)"


@mcp.tool(annotations=RO)
@_safe
def project_summary() -> str:
    """What kind of project this is: language/stack, how to build/run/test it,
    from config files present (pyproject.toml, package.json, Cargo.toml, Makefile,
    justfile, etc). Prefer this over guessing commands from training data."""
    if ROOT is None:
        return "refused: no workspace"
    out = [f"root: {ROOT}"]
    checks = [
        ("pyproject.toml", "Python (pyproject)"), ("requirements.txt", "Python (pip)"),
        ("package.json", "Node.js"), ("Cargo.toml", "Rust"), ("go.mod", "Go"),
        ("Gemfile", "Ruby"), ("pom.xml", "Java (Maven)"), ("build.gradle", "Java/Kotlin (Gradle)"),
        ("Dockerfile", "Docker"), ("docker-compose.yml", "Docker Compose"), ("compose.yaml", "Docker Compose"),
    ]
    stack = [label for fname, label in checks if (ROOT / fname).exists()]
    out.append("stack: " + (", ".join(stack) if stack else "unknown"))
    pkg = ROOT / "package.json"
    if pkg.exists():
        try:
            import json
            scripts = json.loads(pkg.read_text()).get("scripts", {})
            if scripts:
                out.append("npm scripts: " + ", ".join(f"{k}" for k in list(scripts)[:15]))
        except (OSError, ValueError):
            pass
    for fname, label in (("Makefile", "make targets"), ("justfile", "just recipes"), ("Justfile", "just recipes")):
        f = ROOT / fname
        if f.exists():
            targets = re.findall(r"^([A-Za-z0-9_.-]+):", f.read_text(errors="replace"), re.M)
            if targets:
                out.append(f"{label}: " + ", ".join(targets[:15]))
    readme = next((ROOT / n for n in ("README.md", "readme.md", "README.rst", "README") if (ROOT / n).exists()), None)
    if readme:
        head = readme.read_text(errors="replace")[:800]
        out.append(f"README (first 800 chars):\n{head}")
    return redact("\n".join(out))


if __name__ == "__main__":
    mcp.run()
