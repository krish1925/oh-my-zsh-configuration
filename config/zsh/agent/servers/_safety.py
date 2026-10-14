"""_safety.py — deny-list, redaction, and skip-dirs shared by workspace.py and
granted.py (any MCP server that reads real files off disk). Pure data/functions,
no side effects at import time, so importing this never triggers workspace.py's
own git-root detection or registers anything on its `mcp` object.
"""

from __future__ import annotations

import re

SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "target",
             ".next", ".nuxt", ".cache", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox"}

DENY = re.compile(
    r"(^|/)(\.env(\..*)?|\.ssh|\.aws|\.gnupg|\.netrc|\.npmrc|\.pypirc|\.pgpass|"
    r"id_[a-z0-9]+(\.pub)?|.*\.(pem|key|p12|pfx|keychain-db|asc)|"
    r"credentials(\.json)?|secrets?\.(ya?ml|json|toml)|\.git/config|\.git/credentials)$", re.I)

# keep in sync with _ZAI_REDACT_PL in ai.zsh / mcp/shell_history.py
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
