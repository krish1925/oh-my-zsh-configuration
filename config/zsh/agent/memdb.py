"""memdb.py — T2 episodic memory (MEMORY_VISION_PLAN §3e): a local, on-disk,
keyword-searchable log of past `??` turns. Plain SQLite FTS5, no embeddings,
no agentic indexing step — per the plan's own research review, that's what
actually wins on accuracy AND construction time at this model/hardware scale.

Not under $ZSH_CACHE (that directory gets wiped — see the plan's §8 pitfalls).
One short-lived connection per `??` invocation; agent.py is not a daemon.
"""

from __future__ import annotations

import os
import re
import sqlite3
import sys
import time
from pathlib import Path

DB_PATH = Path(os.environ.get("ZAH_DB", str(Path.home() / ".local/share/zsh/agent.db")))
RETENTION_DAYS = float(os.environ.get("ZAH_RECALL_RETENTION_DAYS", "90"))

_SCHEMA = """
CREATE TABLE IF NOT EXISTS turns(
    id INTEGER PRIMARY KEY, t REAL, cwd TEXT, q TEXT, a TEXT,
    tools TEXT, tainted INTEGER, image_sha TEXT);
CREATE VIRTUAL TABLE IF NOT EXISTS turns_fts USING fts5(
    q, a, content='turns', content_rowid='id', tokenize='porter unicode61');
CREATE TRIGGER IF NOT EXISTS turns_ai AFTER INSERT ON turns BEGIN
    INSERT INTO turns_fts(rowid, q, a) VALUES (new.id, new.q, new.a);
END;
CREATE TRIGGER IF NOT EXISTS turns_ad AFTER DELETE ON turns BEGIN
    INSERT INTO turns_fts(turns_fts, rowid, q, a) VALUES('delete', old.id, old.q, old.a);
END;
CREATE TRIGGER IF NOT EXISTS turns_au AFTER UPDATE ON turns BEGIN
    INSERT INTO turns_fts(turns_fts, rowid, q, a) VALUES('delete', old.id, old.q, old.a);
    INSERT INTO turns_fts(rowid, q, a) VALUES (new.id, new.q, new.a);
END;
CREATE TABLE IF NOT EXISTS images(
    sha TEXT PRIMARY KEY, t REAL, path TEXT, mode TEXT,
    ocr TEXT, caption TEXT, question TEXT);
"""


def connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=3)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(_SCHEMA)
    conn.commit()
    return conn


def record_turn(conn: sqlite3.Connection, q: str, a: str, tools_used: list[str],
                 tainted: bool, image_sha: str | None, cwd: str) -> None:
    conn.execute(
        "INSERT INTO turns(t, cwd, q, a, tools, tainted, image_sha) VALUES (?,?,?,?,?,?,?)",
        (time.time(), cwd, q[:4000], a[:4000], ",".join(tools_used)[:500], int(tainted), image_sha))
    conn.commit()


_TERM = re.compile(r"\w+")

# Words that carry no search signal but show up constantly in real questions
# ("what did we decide about docker" -> only "decide"/"docker" should matter).
# Dropping them AND using OR (not the FTS5 default AND) is what makes natural-
# language queries actually match rows instead of requiring every word present.
_STOPWORDS = frozenset("""
    a an the of to in on at is are was were do does did i we you it that this
    what who when where why how about last time yesterday today remember recall
    earlier before previous my our just did have has had be been being
""".split())


def _fts_query(text: str, require_all: bool = False) -> str:
    """Quote every term individually so user text can never be read as FTS5 query
    syntax (a literal `"a" OR b*` in someone's question must search for those
    characters, not run boolean/prefix logic) — MEMORY_VISION_PLAN §3e/§9.

    require_all=False (search/recall): join with OR — bm25 ranks multi-term
    matches higher anyway — so a real question doesn't have to match every
    single word to return anything.
    require_all=True (forget): join with AND (the FTS5 default). A hard delete
    should stay narrow; under-matching just means running it again, but
    over-matching destroys data."""
    terms = [t for t in _TERM.findall(text.lower())[:16] if t not in _STOPWORDS]
    if not terms:
        terms = _TERM.findall(text.lower())[:16]   # all-stopword query: fall back rather than match nothing
    joiner = " " if require_all else " OR "
    return joiner.join('"' + t.replace('"', '') + '"' for t in terms)


def search(conn: sqlite3.Connection, query: str, limit: int = 3) -> list[dict]:
    fts = _fts_query(query)
    if not fts:
        return []
    limit = max(1, min(int(limit), 5))
    try:
        rows = conn.execute(
            "SELECT turns.id, turns.t, turns.cwd, turns.q, turns.a, turns.tainted FROM turns_fts "
            "JOIN turns ON turns.id = turns_fts.rowid "
            "WHERE turns_fts MATCH ? ORDER BY bm25(turns_fts) LIMIT ?",
            (fts, limit)).fetchall()
    except sqlite3.OperationalError as e:
        print(f"memdb: recall query failed: {e}", file=sys.stderr)
        return []
    return [{"id": r[0], "t": r[1], "cwd": r[2], "q": r[3], "a": r[4], "tainted": bool(r[5])}
            for r in rows]


def prune_old(conn: sqlite3.Connection, days: float = RETENTION_DAYS) -> int:
    cutoff = time.time() - days * 86400
    cur = conn.execute("DELETE FROM turns WHERE t < ?", (cutoff,))
    conn.commit()
    return cur.rowcount


def forget(conn: sqlite3.Connection, query: str) -> int:
    """`ai-memory forget <query>` — delete matching rows outright (your data,
    your delete button; not a decay, a hard delete)."""
    fts = _fts_query(query, require_all=True)
    if not fts:
        return 0
    ids = [r[0] for r in conn.execute(
        "SELECT rowid FROM turns_fts WHERE turns_fts MATCH ?", (fts,)).fetchall()]
    if not ids:
        return 0
    conn.executemany("DELETE FROM turns WHERE id=?", [(i,) for i in ids])
    conn.commit()
    return len(ids)


def stats(conn: sqlite3.Connection) -> dict:
    n_turns = conn.execute("SELECT COUNT(*) FROM turns").fetchone()[0]
    n_images = conn.execute("SELECT COUNT(*) FROM images").fetchone()[0]
    oldest = conn.execute("SELECT MIN(t) FROM turns").fetchone()[0]
    return {"turns": n_turns, "images": n_images, "oldest_t": oldest,
            "db_bytes": DB_PATH.stat().st_size if DB_PATH.exists() else 0}


# ------------------------------------------------------------------ CLI (for ai-memory in ai.zsh)
if __name__ == "__main__":
    import sys as _sys

    _cmd = _sys.argv[1] if len(_sys.argv) > 1 else ""
    _conn = connect()
    if _cmd == "forget":
        _q = " ".join(_sys.argv[2:]).strip()
        if not _q:
            print("usage: memdb.py forget <query>", file=_sys.stderr)
            _sys.exit(1)
        # preview with the SAME (AND) semantics forget() will actually use — search()'s OR
        # semantics would show a broader, misleading set of rows here
        _fts_and = _fts_query(_q, require_all=True)
        _matches = []
        if _fts_and:
            _rows = _conn.execute(
                "SELECT turns.id, turns.t, turns.q FROM turns_fts JOIN turns ON turns.id = turns_fts.rowid "
                "WHERE turns_fts MATCH ? ORDER BY bm25(turns_fts)", (_fts_and,)).fetchall()
            _matches = [{"t": r[1], "q": r[2]} for r in _rows]
        if not _matches:
            print(f"no rows match {_q!r}")
            _sys.exit(0)
        for r in _matches:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(r["t"]))
            print(f"  [{when}] {r['q'][:70]}")
        _sys.stdout.flush()   # the row list above and this prompt (on stderr) can interleave wrong when piped
        print(f"delete {len(_matches)} matching row(s)? [y/N] ", end="", file=_sys.stderr)
        if input().strip().lower() != "y":
            print("cancelled")
            _sys.exit(0)
        n = forget(_conn, _q)
        print(f"deleted {n} row(s)")
    elif _cmd == "stats":
        s = stats(_conn)
        age = f"{(time.time() - s['oldest_t']) / 86400:.0f} days" if s["oldest_t"] else "n/a"
        print(f"turns: {s['turns']}  images: {s['images']}  oldest: {age} ago  "
              f"db: {s['db_bytes'] / 1024:.0f} KB  ({DB_PATH})")
    else:
        print("usage: memdb.py {forget <query>|stats}", file=_sys.stderr)
        _sys.exit(1)
