#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2.2,<3"]
# ///
"""shell-history — your real shell habits as a read-only MCP server.

Lets Claude Code answer "how do I usually run tests in this repo" from what
you actually ran (atuin's SQLite history: command, cwd, exit code, session,
time) instead of guessing.

Read-only: the database is opened with mode=ro. Secrets are redacted with
the same rules as ai.zsh before anything is returned.

Register once:
    claude mcp add --scope user shell-history -- uv run --script ~/.config/zsh/mcp/shell_history.py
"""

from __future__ import annotations

import os
import re
import sqlite3
import time
from pathlib import Path

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

DB = Path(os.environ.get("ATUIN_DB_PATH")
          or Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "atuin/history.db")
BOOKMARKS = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zsh/bookmarks"
NS = 1_000_000_000

mcp = MCPServer(
    "shell-history",
    instructions="The user's real shell history (atuin): what they run, where, and whether it worked. "
                 "Prefer usual_commands / how_to_run over guessing how a project is built or tested.",
)
RO = ToolAnnotations(readOnlyHint=True, openWorldHint=False)

# ---- redaction: keep in sync with _ZAI_REDACT_PL in ai.zsh -----------------
_REDACT = [
    (re.compile(r"\bsk-(?:ant-|proj-|live-|test-)?[A-Za-z0-9_-]{16,}"), "[redacted]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,})"), "[redacted]"),
    (re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"), "[redacted]"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"), "[redacted]"),
    (re.compile(r"\bAIza[0-9A-Za-z_-]{30,}"), "[redacted]"),
    (re.compile(r"\b(?:hf|npm|pypi|dop_v1)_[A-Za-z0-9_-]{20,}"), "[redacted]"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"), "[redacted-jwt]"),
    (re.compile(r"(\b(?:Bearer|Basic|Token)\s+)[^\s\"']+", re.I), r"\1[redacted]"),
    (re.compile(r"(\b[A-Za-z0-9_]*(?:password|passwd|passphrase|secret|token|api[_-]?key|access[_-]?key|"
                r"private[_-]?key|credentials?)s?(?:[_-]?key)?\s*[=:]\s*)(\"[^\"]*\"|'[^']*'|[^\s&;|]+)", re.I),
     r"\1[redacted]"),
    (re.compile(r"(--?(?:password|passwd|token|secret|api-key|key)[= ])(\S+)", re.I), r"\1[redacted]"),
    (re.compile(r"(://[^/\s:@]+:)[^@\s/]+@"), r"\1[redacted]@"),
]


def redact(s: str) -> str:
    for rx, rep in _REDACT:
        s = rx.sub(rep, s)
    return s


def q(sql: str, args: tuple = ()) -> list[sqlite3.Row]:
    if not DB.exists():
        raise RuntimeError(f"atuin database not found at {DB}")
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=3)
    con.row_factory = sqlite3.Row
    try:
        return con.execute(sql, args).fetchall()
    finally:
        con.close()


def ago(ts_ns: int) -> str:
    d = time.time() - ts_ns / NS
    for unit, sec in (("d", 86400), ("h", 3600), ("m", 60)):
        if d >= sec:
            return f"{int(d // sec)}{unit} ago"
    return "just now"


def repo_root(path: str) -> str:
    p = Path(path).expanduser().resolve()
    for c in (p, *p.parents):
        if (c / ".git").exists():
            return str(c)
    return str(p)


def scope_sql(cwd: str | None, include_subdirs: bool) -> tuple[str, tuple]:
    if not cwd:
        return "", ()
    d = str(Path(cwd).expanduser().resolve())
    if include_subdirs:
        return " AND (cwd = ? OR cwd LIKE ? ESCAPE '\\')", (d, d.replace("%", r"\%").replace("_", r"\_") + "/%")
    return " AND cwd = ?", (d,)


BASE = " deleted_at IS NULL AND instr(command, char(10)) = 0 AND length(command) < 500"


@mcp.tool(annotations=RO)
def usual_commands(cwd: str, include_subdirs: bool = True, limit: int = 25) -> str:
    """Commands the user most often runs successfully in a directory (default:
    the whole repo containing it). Use first when asked how something is
    usually done in a project: build, test, run, deploy, lint."""
    root = repo_root(cwd) if include_subdirs else cwd
    s, a = scope_sql(root, include_subdirs)
    rows = q(f"""SELECT command, COUNT(*) n, MAX(timestamp) t FROM history
                 WHERE {BASE} AND exit = 0 {s}
                 GROUP BY command ORDER BY n DESC, t DESC LIMIT ?""", (*a, limit))
    if not rows:
        return f"no history for {root}"
    return f"most-run successful commands under {root}:\n" + "\n".join(
        f"{r['n']:4d}x  {redact(r['command'])}   (last {ago(r['t'])})" for r in rows)


@mcp.tool(annotations=RO)
def how_to_run(cwd: str, limit: int = 12) -> str:
    """How the user actually tests / builds / runs / lints the project at cwd,
    from their history (successful runs only, whole repo)."""
    root = repo_root(cwd)
    s, a = scope_sql(root, True)
    pat = (r"(^|\s)(pytest|tox|nox|uv run|poetry run|python -m|npm (run |test)|pnpm|yarn|bun |cargo (test|build|run)|"
           r"go (test|build|run)|make|just|docker compose|mvn|gradle|ruff|mypy|eslint|tsc|vitest|jest|sam |cdk )")
    rx = re.compile(pat)
    rows = q(f"""SELECT command, COUNT(*) n, MAX(timestamp) t FROM history
                 WHERE {BASE} AND exit = 0 {s}
                 GROUP BY command ORDER BY n DESC, t DESC LIMIT 2000""", a)
    hits = [r for r in rows if rx.search(r["command"])][:limit]
    if not hits:
        return f"no test/build/run commands found in history under {root}"
    return f"under {root}, the user runs:\n" + "\n".join(
        f"{r['n']:4d}x  {redact(r['command'])}   (last {ago(r['t'])})" for r in hits)


@mcp.tool(annotations=RO)
def search_history(query: str, cwd: str | None = None, successful_only: bool = True, limit: int = 30) -> str:
    """Find past commands containing ALL of the space-separated words in query
    (case-insensitive substring match), newest first. Optionally restricted
    to a directory tree."""
    words = [w for w in query.split() if w][:8]
    if not words:
        return "empty query"
    cond = " AND ".join("instr(lower(command), lower(?)) > 0" for _ in words)
    s, a = scope_sql(cwd, True)
    rows = q(f"""SELECT command, cwd, exit, MAX(timestamp) t, COUNT(*) n FROM history
                 WHERE {BASE} AND {cond} {"AND exit = 0" if successful_only else ""} {s}
                 GROUP BY command ORDER BY t DESC LIMIT ?""", (*words, *a, limit))
    if not rows:
        return "no matches"
    home = str(Path.home())
    return "\n".join(f"{ago(r['t']):>9}  {r['n']:3d}x  [{r['cwd'].replace(home, '~')}]  {redact(r['command'])}"
                     for r in rows)


@mcp.tool(annotations=RO)
def what_follows(command_prefix: str, cwd: str | None = None, limit: int = 10) -> str:
    """What the user typically runs right after commands starting with
    command_prefix (same shell session). Reveals workflows, e.g. what comes
    after `git add` or after starting a dev server."""
    s, a = scope_sql(cwd, True)
    rows = q(f"""WITH o AS (
                   SELECT command a, cwd, LEAD(command) OVER (PARTITION BY session ORDER BY timestamp) b,
                          LEAD(exit) OVER (PARTITION BY session ORDER BY timestamp) eb
                   FROM history WHERE {BASE})
                 SELECT b, COUNT(*) n FROM o
                 WHERE substr(a, 1, ?) = ? AND b IS NOT NULL AND eb = 0 AND a <> b {s}
                 GROUP BY b ORDER BY n DESC LIMIT ?""", (len(command_prefix), command_prefix, *a, limit))
    if not rows:
        return f"no data on what follows `{command_prefix}`"
    return f"after `{command_prefix}` the user usually runs:\n" + "\n".join(
        f"{r['n']:4d}x  {redact(r['b'])}" for r in rows)


@mcp.tool(annotations=RO)
def failures_and_fixes(cwd: str | None = None, days: int = 60, limit: int = 20) -> str:
    """Recent failing commands and the successful command the user ran next in
    the same session — usually the fix. Good for 'why does X keep failing'
    and for learning the user's local gotchas."""
    s, a = scope_sql(cwd, True)
    since = int((time.time() - days * 86400) * NS)
    rows = q(f"""WITH o AS (
                   SELECT command a, exit ea, cwd, timestamp t,
                          LEAD(command) OVER (PARTITION BY session ORDER BY timestamp) b,
                          LEAD(exit) OVER (PARTITION BY session ORDER BY timestamp) eb
                   FROM history WHERE {BASE})
                 SELECT a, ea, b, MAX(t) t, COUNT(*) n FROM o
                 WHERE ea NOT IN (0, 130, -1) AND t > ? AND (eb = 0 OR b IS NULL) {s}
                 GROUP BY a, b ORDER BY t DESC LIMIT ?""", (since, *a, limit))
    if not rows:
        return "no recent failures"
    out = []
    for r in rows:
        line = f"{ago(r['t']):>9}  exit {r['ea']}: {redact(r['a'])}"
        if r["b"]:
            line += f"\n           then: {redact(r['b'])}"
        out.append(line)
    return "\n".join(out)


@mcp.tool(annotations=RO)
def bookmarks() -> str:
    """The user's named directories (zsh `mark`): name → path. `~name` works in their shell."""
    if not BOOKMARKS.exists():
        return "no bookmarks"
    lines = [l.split("\t", 1) for l in BOOKMARKS.read_text().splitlines() if "\t" in l]
    return "\n".join(f"~{n} → {p}" for n, p in lines) or "no bookmarks"


@mcp.tool(annotations=RO)
def busiest_directories(days: int = 30, limit: int = 15) -> str:
    """Where the user has been working lately, by number of commands run."""
    since = int((time.time() - days * 86400) * NS)
    rows = q(f"""SELECT cwd, COUNT(*) n, MAX(timestamp) t FROM history
                 WHERE deleted_at IS NULL AND timestamp > ? GROUP BY cwd ORDER BY n DESC LIMIT ?""", (since, limit))
    home = str(Path.home())
    return "\n".join(f"{r['n']:5d}  {r['cwd'].replace(home, '~')}   (last {ago(r['t'])})" for r in rows)


if __name__ == "__main__":
    mcp.run()
