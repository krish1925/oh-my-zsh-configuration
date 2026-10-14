"""dirgrants.py — time-limited, explicit-consent grants to browse a directory OUTSIDE
the current project's workspace.py jail (e.g. "look at my other repo at ~/code/foo too").

The grant/deny decision (a real y/N read from /dev/tty via guard.ask) happens once, in
agent.py's request_directory_access dispatch — this module only stores the OUTCOME and
is the single source of truth every subsequent read checks against. A grant is never
permanent: `active_root_for()` treats an expired entry as if it were never granted, and
nothing here can renew itself — only a fresh request_directory_access call (which means
a fresh human y/N) can extend access past 7 days.

Not under $ZSH_CACHE (that directory gets wiped) — same rationale as memdb.py.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fsutil import atomic_write_text, locked  # noqa: E402

GRANTS_PATH = Path(os.environ.get("ZAH_GRANTS_PATH", str(Path.home() / ".local/share/zsh/dir-grants.json")))
DEFAULT_DAYS = float(os.environ.get("ZAH_GRANT_DAYS", "7"))


def _forbidden(p: Path) -> bool:
    """Never grant $HOME or / itself — that's not "a directory", that's everything.
    Mirrors workspace.py's _find_root() rule for its own (fixed) jail."""
    return p in (Path.home(), Path("/"))


def _load_raw() -> dict[str, float]:
    """The grants file as {absolute path: expiry epoch}. Missing → {}. Anything malformed
    (bad JSON, wrong types, relative paths) is IGNORED entry by entry — a damaged file can
    only ever grant LESS, never more."""
    try:
        data = json.loads(GRANTS_PATH.read_text())
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {p: float(e) for p, e in data.items()
            if isinstance(p, str) and os.path.isabs(p) and isinstance(e, (int, float)) and not isinstance(e, bool)}


def _save_raw(grants: dict[str, float]) -> None:
    """Atomic (readers never see a half-written file), private (0600). Raises OSError on
    failure — callers must not pretend a grant or a revoke happened when it didn't."""
    atomic_write_text(GRANTS_PATH, json.dumps(grants, indent=1), mode=0o600)


def _quarantine_if_corrupt() -> None:
    """A file that exists but does not parse is moved aside before we overwrite it, so a
    bad write elsewhere never silently destroys the record of what you approved."""
    try:
        json.loads(GRANTS_PATH.read_text())
    except FileNotFoundError:
        pass
    except (OSError, ValueError):
        try:
            os.replace(GRANTS_PATH, str(GRANTS_PATH) + ".corrupt")
        except OSError:
            pass


def load() -> dict[str, float]:
    """{resolved absolute path: expiry epoch} for grants that are live RIGHT NOW. Pure read:
    no locking and no writing, so the read-only granted.py server can call it on every
    request. Expired entries are simply not returned (they are pruned on the next grant)."""
    now = time.time()
    return {p: exp for p, exp in _load_raw().items() if exp > now}


def _update(mutate) -> object:
    """Read-modify-write under the lock, dropping expired entries as it goes."""
    with locked(GRANTS_PATH):
        _quarantine_if_corrupt()
        now = time.time()
        grants = {p: e for p, e in _load_raw().items() if e > now}
        result = mutate(grants)
        _save_raw(grants)
        return result


def grant(path: Path, days: float = DEFAULT_DAYS) -> float:
    """Record an explicit-consent grant for `path` (must already be resolved+validated
    by the caller — this function does not re-check _forbidden, since the y/N the human
    just answered was ABOUT this exact path). Returns the expiry epoch. Raises OSError if
    it could not be saved (then NOTHING was granted)."""
    expiry = time.time() + days * 86400

    def add(g: dict[str, float]) -> float:
        g[str(path)] = expiry
        return expiry
    return _update(add)  # type: ignore[return-value]


def active_root_for(path: Path) -> Path | None:
    """None if nothing covers `path`; otherwise the (most specific) granted root that
    does. A grant on a directory covers everything under it, same as workspace.py's own
    jail covers its whole subtree — you don't re-ask per-file within an approved folder."""
    grants = load()
    path = path.resolve()
    best: Path | None = None
    for root_str in grants:
        root = Path(root_str)
        if path == root or root in path.parents:
            if best is None or len(root.parts) > len(best.parts):
                best = root
    return best


def revoke(path: Path) -> bool:
    """`ai-access revoke <path>` — hard delete, not decay. Matches an exact granted
    root (not a path merely underneath one) so a slightly-off path can't silently no-op."""
    key = str(path.resolve())

    def drop(g: dict[str, float]) -> bool:
        return g.pop(key, None) is not None
    return bool(_update(drop))


def revoke_all() -> int:
    def drop(g: dict[str, float]) -> int:
        n = len(g)
        g.clear()
        return n
    return int(_update(drop))


def list_grants() -> list[dict]:
    now = time.time()
    return sorted(
        ({"path": p, "expires_at": exp, "days_left": round((exp - now) / 86400, 1)} for p, exp in load().items()),
        key=lambda g: g["expires_at"])


if __name__ == "__main__":
    import sys as _sys

    _cmd = _sys.argv[1] if len(_sys.argv) > 1 else ""
    if _cmd == "list":
        gs = list_grants()
        if not gs:
            print("no active directory grants")
        for g in gs:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(g["expires_at"]))
            print(f"  {g['path']}  (expires {when}, {g['days_left']}d left)")
    elif _cmd == "revoke":
        target = " ".join(_sys.argv[2:]).strip()
        if not target:
            print("usage: dirgrants.py revoke <path>", file=_sys.stderr)
            _sys.exit(1)
        ok = revoke(Path(target).expanduser())
        print(f"revoked: {target}" if ok else f"no active grant for: {target}")
    elif _cmd == "revoke-all":
        n = revoke_all()
        print(f"revoked {n} grant(s)")
    else:
        print("usage: dirgrants.py {list|revoke <path>|revoke-all}", file=_sys.stderr)
        _sys.exit(1)
