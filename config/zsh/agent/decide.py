"""decide.py — typed decisions from a local Winnow server (see DECIDER_PLAN.md).

Winnow-E4B (EldanRing/winnow-inference) answers "which option?" from candidate-letter logits in ONE forward
pass. The server owns the prompt format (native/protocol.h), the letter labelling, the logits and the
temperature-scaled softmax; this module only builds typed requests from agent/decide_spec.json, reads typed
JSON back, and computes the margin. It never builds a prompt, never maps letters, never parses text.
Standard library only (agent.py runs under `uv run --script`, the eval runner under plain python3).

    decide(task, state, ...)          -> Decision            one question, one call
    decide_swapped(task, state, ...)  -> Decision            option order reversed and back; both must agree
    Decision.fallback_reason is None on success, else one of
        disabled | unfitted | server_down | timeout | bad_response
    Callers treat ANY fallback as "do exactly what you did before this feature existed".
    bad_response is a bug, not a normal answer: the raw reply is saved to $ZSH_CACHE/decide-debug/ and the path
    is printed to stderr.
"""

from __future__ import annotations

import hashlib
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
SPEC_PATH = Path(os.environ.get("ZDEC_SPEC", HERE / "decide_spec.json"))
_spec_cache: dict | None = None


def load_spec(path: Path | None = None) -> dict:
    global _spec_cache
    if path is not None:
        return json.loads(Path(path).read_text())
    if _spec_cache is None:
        _spec_cache = json.loads(SPEC_PATH.read_text())
    return _spec_cache


@dataclass
class Decision:
    label: str | None = None                  # the option KEY the server chose, None on fallback
    margin: float = 0.0                       # p(best) - p(runner-up), probabilities over this request's options
    probs: dict = field(default_factory=dict) # option key -> probability (server-side softmax, calibrated temperature)
    logits: list = field(default_factory=list)  # candidate logits in the order the options were sent (diagnostics)
    ms: float = 0.0
    fallback_reason: str | None = None
    swap_ok: bool | None = None               # only set by decide_swapped
    order: list = field(default_factory=list) # the option order actually sent

    @property
    def ok(self) -> bool:
        return self.fallback_reason is None and self.label is not None


def primary_threshold(task: dict):
    t = task.get("thresholds", {})
    return t["delta"] if "delta" in t else t.get("accept_margin")


def build_request(task: str, state, *, options: dict | None = None, order: list | None = None,
                  spec: dict | None = None, diagnostics: bool = True, also_reversed: bool = False) -> dict:
    """The exact typed body sent to /v1/systemone. `options` is required for tasks with options == "dynamic";
    `order` re-orders the options (the swap check reverses it) — option KEYS stay the same, so callers never
    have to translate labels."""
    spec = spec or load_spec()
    tk, be = spec["tasks"][task], spec["backend"]
    opts = options if options is not None else tk["options"]
    if opts == "dynamic":
        raise ValueError(f"task {task!r} needs options=…")
    if order is not None:
        if sorted(order) != sorted(opts):
            raise ValueError("order must be a permutation of the option keys")
        opts = {k: opts[k] for k in order}
    questions = {"q": {"type": tk["type"], "instructions": tk["instructions"], "criteria": opts}}
    if also_reversed:   # the swap check as a second question in the SAME request (state is prefilled once, branches run in parallel)
        questions["r"] = {"type": tk["type"], "instructions": tk["instructions"], "criteria": dict(reversed(list(opts.items())))}
    return {
        "model": be["model"],
        "state": state,
        "questions": questions,
        "winnow": {"temperature": be["temperature"], "diagnostics": diagnostics},
    }


def _reachable(url: str, timeout: float) -> bool:
    u = urlparse(url)
    try:
        with socket.create_connection((u.hostname or "127.0.0.1", u.port or 80), timeout):
            return True
    except OSError:
        return False


def _cache_dir() -> Path:
    return Path(os.environ.get("ZSH_CACHE") or Path.home() / ".cache/zsh")


def save_debug(raw: bytes | str, why: str, task: str) -> Path:
    d = _cache_dir() / "decide-debug"
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{int(time.time())}-{task}-{why}.txt"
    p.write_bytes(raw if isinstance(raw, bytes) else raw.encode())
    return p


def parse_answer(resp: dict, keys: list[str], qid: str = "q") -> tuple[str, dict, list]:
    """typed JSON -> (label, probs, logits). Raises ValueError on anything that isn't exactly what the API documents."""
    a = resp["answers"][qid]
    if a.get("type") != "choice":
        raise ValueError(f"expected a choice answer, got {a.get('type')!r}")
    probs = a["probabilities"]
    if sorted(probs) != sorted(keys):
        raise ValueError(f"probability keys {sorted(probs)} != option keys {sorted(keys)}")
    if abs(sum(probs.values()) - 1.0) > 1e-3:
        raise ValueError(f"probabilities sum to {sum(probs.values())}")
    logits = (a.get("winnow") or {}).get("logits", [])
    return a["choice"], {k: float(v) for k, v in probs.items()}, list(logits)


def margin_of(probs: dict) -> float:
    ranked = sorted(probs.values(), reverse=True)
    return ranked[0] - (ranked[1] if len(ranked) > 1 else 0.0)


def decide(task: str, state, *, options: dict | None = None, order: list | None = None,
           url: str | None = None, spec: dict | None = None, require_fitted: bool = True,
           log: bool = True, both: bool = False) -> Decision:
    t0 = time.perf_counter()
    d = Decision()
    spec = spec or load_spec()
    tk, be = spec["tasks"][task], spec["backend"]

    def done(reason: str | None) -> Decision:
        d.fallback_reason = reason
        d.ms = (time.perf_counter() - t0) * 1000
        if log:
            log_decision(task, state, d)
        return d

    if os.environ.get("ZDEC", "1") == "0":
        return done("disabled")
    if require_fitted and primary_threshold(tk) is None:
        return done("unfitted")
    url = (url or os.environ.get("ZDEC_URL") or be["url"]).rstrip("/")
    body = build_request(task, state, options=options, order=order, spec=spec, also_reversed=both)
    d.order = list(body["questions"]["q"]["criteria"])
    if not _reachable(url, be["connect_timeout_s"]):
        return done("server_down")
    req = urllib.request.Request(url + "/v1/systemone", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    key = os.environ.get("ZDEC_KEY")
    if key:
        req.add_header("Authorization", f"Bearer {key}")
    raw = b""
    try:
        with urllib.request.urlopen(req, timeout=be["timeout_s"]) as r:
            raw = r.read()
        resp = json.loads(raw)
        d.label, d.probs, d.logits = parse_answer(resp, d.order)
        d.margin = margin_of(d.probs)
        if both:
            l2, p2, _ = parse_answer(resp, d.order, "r")
            d.swap_ok = d.label == l2
            d.margin = min(d.margin, margin_of(p2))
            if not d.swap_ok:
                d.label = None
        try:   # Winnow's own idle timer (ai.zsh _ZDW_STAMP): a decision is "use"
            (_cache_dir() / "ai-winnow-last-use").touch()
        except OSError:
            pass
    except (socket.timeout, TimeoutError):
        return done("timeout")
    except urllib.error.HTTPError as e:
        p = save_debug(e.read(), f"http{e.code}", task)
        print(f"decide: server returned HTTP {e.code}; raw reply saved to {p}", file=sys.stderr)
        return done("bad_response")
    except urllib.error.URLError as e:
        return done("timeout" if isinstance(e.reason, (socket.timeout, TimeoutError)) else "server_down")
    except (KeyError, ValueError, TypeError) as e:
        p = save_debug(raw or b"<empty>", "parse", task)
        print(f"decide: unexpected reply ({e!r}); raw reply saved to {p}", file=sys.stderr)
        return done("bad_response")
    return done(None)


def decide_swapped(task: str, state, *, options: dict | None = None, **kw) -> Decision:
    """D5: the options in the given order AND reversed, asked as two questions in one request; both must pick the same
    key. margin = the smaller of the two. label is None (swap_ok False) when they disagree — 'uncertain', never a decision."""
    return decide(task, state, options=options, both=True, **kw)


# ------------------------------------------------------------------ logging (D15)
def _redact(text: str) -> str:
    try:
        from guard import redact_secrets   # agent/guard.py, when importable
        return redact_secrets(text)
    except Exception:
        return "[input not logged: redactor unavailable]"


def log_decision(task: str, state, d: Decision) -> None:
    """One JSONL line, redacted preview ≤300 chars, well under 4 KB so an O_APPEND write is atomic (no lock)."""
    try:
        text = state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)
        cache = _cache_dir()
        cache.mkdir(parents=True, exist_ok=True)
        rec = {"t": int(time.time()), "task": task, "chosen": d.label, "margin": round(d.margin, 4),
               "swap_ok": d.swap_ok, "ms": round(d.ms), "fallback_reason": d.fallback_reason,
               "input_sha": hashlib.sha256(text.encode()).hexdigest()[:12],
               "input_preview": _redact(text)[:300]}
        line = (json.dumps(rec, ensure_ascii=False) + "\n").encode()[:4000]
        fd = os.open(cache / "decide.jsonl", os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(fd, line)
        finally:
            os.close(fd)
    except OSError:
        pass
