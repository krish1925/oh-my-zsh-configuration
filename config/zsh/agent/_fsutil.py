"""_fsutil.py — the same rules as lib.zsh, for the Python side.

Several `??` runs (one per terminal tab), the shell, and background jobs share small
state files. Two rules keep them coherent:

  locked(path)        one writer at a time — a POSIX record lock (fcntl.lockf), the same
                      kind zsh's `zsystem flock` takes, released by the kernel if the
                      holder dies. Readers never need it: writes are atomic.
  atomic_write_text   temp file in the same directory + fsync + rename: a reader sees the
                      whole old file or the whole new one; a crash leaves the old one.
"""
from __future__ import annotations

import contextlib
import fcntl
import os
import tempfile
import time
from pathlib import Path


@contextlib.contextmanager
def locked(path, timeout: float = 20.0):
    """Exclusive lock on <path>.lock for the with-block. Raises TimeoutError, never skips silently."""
    lk = Path(str(path) + ".lock")
    lk.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lk, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"could not lock {lk.name} within {timeout:.0f}s")
                time.sleep(0.01)
        yield
    finally:
        os.close(fd)          # closing releases the lock


def atomic_write_text(path, text: str, mode: int | None = None) -> None:
    """Replace `path` (following a symlink) with `text` all-or-nothing. `mode` sets the
    permissions of a NEW file; an existing file keeps its own."""
    real = Path(os.path.realpath(path))
    real.parent.mkdir(parents=True, exist_ok=True)
    try:
        keep = os.stat(real).st_mode & 0o7777
    except FileNotFoundError:
        keep = mode if mode is not None else 0o644
    fd, tmp = tempfile.mkstemp(prefix=real.name + ".tmp.", dir=real.parent)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, keep)
        os.replace(tmp, real)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise
