"""mac — read-only MCP server: what is this Mac doing right now.

Every tool runs a FIXED argv (no shell, no user-supplied strings reach a
command line), with a timeout, and only reads. There is deliberately no
tool that changes anything: for that the agent proposes a command and you
press Enter. Clipboard, files, browser history, mail, messages: not exposed.
"""

from __future__ import annotations

import os
import re
import subprocess
import time

from mcp.server.mcpserver import MCPServer
from mcp.types import ToolAnnotations

mcp = MCPServer("mac", instructions="Read-only facts about this Mac: memory, CPU, processes, apps, disk, battery, network.")
RO = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)


def run(*argv: str, timeout: float = 6) -> str:
    try:
        p = subprocess.run(list(argv), capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return (p.stdout or p.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"({argv[0]} failed: {e.__class__.__name__})"


def osa(script: str) -> str:
    return run("/usr/bin/osascript", "-e", script)


def gb(n: float) -> str:
    return f"{n / 1024**3:.1f} GB"


@mcp.tool(annotations=RO)
def system_overview() -> str:
    """macOS version, Mac model, chip, RAM, uptime and load average."""
    info = osa('set s to system info\n'
               'return (computer name of s) & " | " & (system version of s) & " | " & (CPU type of s) & " | " & ((physical memory of s) as text) & " MB"')
    return "\n".join([
        f"AppleScript system info: {info}",
        f"model: {run('/usr/sbin/sysctl', '-n', 'hw.model')}   chip: {run('/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string')}",
        f"cores: {run('/usr/sbin/sysctl', '-n', 'hw.ncpu')}",
        f"uptime/load: {run('/usr/bin/uptime')}",
    ])


@mcp.tool(annotations=RO)
def memory() -> str:
    """RAM: total, used, app memory, wired, compressed, free, swap, and the kernel's memory-pressure level."""
    total = int(run("/usr/sbin/sysctl", "-n", "hw.memsize") or 0)
    vm = run("/usr/bin/vm_stat")
    page = int((re.search(r"page size of (\d+)", vm) or [0, 16384])[1])
    pages = {k.strip().lower(): int(v.strip().rstrip(".")) for k, v in re.findall(r"^([^:]+):\s+(\d+)\.?$", vm, re.M)}
    g = lambda k: pages.get(k, 0) * page
    wired, comp = g("pages wired down"), g("pages occupied by compressor")
    active, inactive, spec, free = g("pages active"), g("pages inactive"), g("pages speculative"), g("pages free")
    purge, anon = g("pages purgeable"), g("anonymous pages")
    app = max(anon - purge, 0)
    used = app + wired + comp
    pressure = run("/usr/bin/memory_pressure", "-Q")
    pct = re.search(r"free percentage:\s*(\d+)%", pressure)
    return "\n".join([
        f"total {gb(total)} · used {gb(used)} (app {gb(app)}, wired {gb(wired)}, compressed {gb(comp)})",
        f"cached files {gb(g("file-backed pages") + purge)} · free {gb(free)}",
        f"swap: {run('/usr/sbin/sysctl', '-n', 'vm.swapusage')}",
        f"memory free percentage (kernel): {pct[1] + '%' if pct else 'n/a'}",
    ])


@mcp.tool(annotations=RO)
def top_processes(sort_by: str = "memory", limit: int = 12) -> str:
    """The heaviest running processes. sort_by: "memory" or "cpu". limit: 1-30."""
    limit = max(1, min(int(limit), 30))
    flag = "-r" if sort_by == "cpu" else "-m"
    out = run("/bin/ps", "-Aceo", "pid,pcpu,pmem,rss,comm", flag)
    lines = out.splitlines()
    rows = []
    for l in lines[1:limit + 1]:
        parts = l.split(None, 4)
        if len(parts) == 5:
            pid, cpu, mem, rss, name = parts
            rows.append(f"{pid:>6}  {cpu:>5}% cpu  {mem:>5}% mem  {int(rss) / 1024:>8.0f} MB  {name}")
    return f"top {len(rows)} by {'cpu' if flag == '-r' else 'memory'}:\n" + "\n".join(rows)


@mcp.tool(annotations=RO)
def running_apps() -> str:
    """Foreground applications that are open right now, and which one is frontmost."""
    out = run("/usr/bin/lsappinfo", "list")
    apps = [m[1] for m in re.finditer(r'^\s*\d+\) "([^"]+)" ASN:(.*?)(?=^\s*\d+\) "|\Z)', out, re.M | re.S)
            if 'type="Foreground"' in m[2]]
    front = run("/usr/bin/lsappinfo", "info", "-only", "name", run("/usr/bin/lsappinfo", "front"))
    front = (re.search(r'="([^"]+)"', front) or [None, "?"])[1]
    return f"frontmost: {front}\nopen apps ({len(apps)}): " + ", ".join(sorted(set(apps)))


@mcp.tool(annotations=RO)
def disk_usage() -> str:
    """Free and used space on the startup disk and mounted volumes."""
    return run("/bin/df", "-H", "-T", "apfs,hfs,exfat,msdos")


@mcp.tool(annotations=RO)
def battery() -> str:
    """Battery charge, charging state, time remaining, and power source."""
    return run("/usr/bin/pmset", "-g", "batt")


@mcp.tool(annotations=RO)
def network_status() -> str:
    """Active network interfaces, local IP addresses, default gateway, and DNS servers (no Wi-Fi scanning)."""
    ips = [f"{i}: {run('/usr/sbin/ipconfig', 'getifaddr', i) or '-'}" for i in ("en0", "en1")]
    route = re.search(r"gateway: (\S+)", run("/sbin/route", "-n", "get", "default"))
    dns = sorted(set(re.findall(r"nameserver\[\d+\] : (\S+)", run("/usr/sbin/scutil", "--dns"))))[:6]
    return "\n".join(ips + [f"gateway: {route[1] if route else '-'}", f"dns: {', '.join(dns) or '-'}"])


@mcp.tool(annotations=RO)
def listening_ports() -> str:
    """Programs listening on TCP ports on this Mac (like `lsof -iTCP -sTCP:LISTEN`)."""
    out = run("/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", timeout=8)
    seen, rows = set(), []
    for l in out.splitlines()[1:]:
        p = l.split()
        if len(p) >= 9 and (p[0], p[8]) not in seen:
            seen.add((p[0], p[8])); rows.append(f"{p[0]:<20} pid {p[1]:<7} {p[8]}")
    return "\n".join(rows[:40]) or "nothing listening"


@mcp.tool(annotations=RO)
def audio_and_display() -> str:
    """Output volume / mute (AppleScript) and connected displays."""
    vol = osa("get volume settings")
    disp = run("/usr/sbin/system_profiler", "SPDisplaysDataType", "-detailLevel", "mini", timeout=10)
    names = re.findall(r"^\s{8}(\S.*):$", disp, re.M)
    res = re.findall(r"Resolution: (.+)", disp)
    return f"volume: {vol}\ndisplays: " + "; ".join(f"{n} ({r})" for n, r in zip(names, res))


# =====================================================================
#  Tier 0 telemetry: no sudo, no TCC (Full Disk Access / Accessibility /
#  Screen Recording / Input Monitoring) needed for anything below. Tier 1
#  (powermetrics, eslogger — both need root) and Tier 2 (Biome, Messages,
#  browser history, Screen Time — all need Full Disk Access) are deliberately
#  NOT implemented: granting Full Disk Access to Terminal hands it to every
#  process started from this shell, not just this agent, and the resulting
#  store (messages, browsing, every menu click) would be the single most
#  sensitive database on the machine. Tier 0 already covers most of what
#  "what is my Mac doing" needs.
# =====================================================================

@mcp.tool(annotations=RO)
def energy_hogs(limit: int = 10) -> str:
    """Which processes are drawing the most energy right now (macOS's own
    per-process power score from `top`, not just raw CPU%)."""
    limit = max(1, min(int(limit), 30))
    out = run("/usr/bin/top", "-l", "2", "-s", "1", "-n", str(limit), "-o", "power",
              "-stats", "pid,command,cpu,power", timeout=8)
    # `-l 2` prints two full reports; the first sample's %CPU/power are often 0
    # (no elapsed interval yet) — keep only the LAST "PID COMMAND..." table.
    # The split pattern consumes the WHOLE header line (through end of line),
    # so what's left starts cleanly at the first data row, not a header fragment.
    tables = re.split(r"(?m)^PID\s+COMMAND.*$\n?", out)
    if len(tables) < 2:
        return out[-1500:] if out else "(no data)"
    rows = [l for l in tables[-1].splitlines() if l.strip()][:limit]
    return "pid      command          %cpu  power\n" + "\n".join(rows)


@mcp.tool(annotations=RO)
def network_by_process(limit: int = 10) -> str:
    """Bytes sent/received per process since this call started sampling (~1s)."""
    limit = max(1, min(int(limit), 30))
    out = run("/usr/bin/nettop", "-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x", timeout=5)
    rows = []
    for line in out.splitlines()[1:]:
        parts = line.split(",")
        if len(parts) >= 3 and parts[0]:
            try:
                bi, bo = int(parts[1] or 0), int(parts[2] or 0)
            except ValueError:
                continue
            if bi or bo:
                rows.append((bi + bo, f"{parts[0]:<28} in {gb(bi)!s:>10}  out {gb(bo)}"))
    rows.sort(reverse=True)
    return "\n".join(r for _, r in rows[:limit]) or "no network activity observed in the sample window"


@mcp.tool(annotations=RO)
def sleep_wake_history(hours: int = 24) -> str:
    """Sleep/wake/dark-wake transitions in the last N hours, from the power log."""
    hours = max(1, min(int(hours), 168))
    out = run("/usr/bin/pmset", "-g", "log", timeout=8)
    # event-type field is padded with 2+ spaces before the tab; a single space
    # (e.g. "Wake Requests") is a different, noisier event type — excluded on purpose
    events = re.findall(r"^(\S+ \S+) \S+\s+(Sleep|Wake|DarkWake)\s{2,}\t?(.*)$", out, re.M)
    cutoff = time.time() - hours * 3600
    rows = []
    for ts, kind, detail in events:
        try:
            t = time.mktime(time.strptime(ts, "%Y-%m-%d %H:%M:%S"))
        except ValueError:
            continue
        if t >= cutoff:
            rows.append(f"{ts}  {kind:<10} {detail.strip()[:100]}")
    return "\n".join(rows[-60:]) if rows else f"no sleep/wake events in the last {hours}h"


@mcp.tool(annotations=RO)
def thermal_state() -> str:
    """Thermal / performance throttling state, if macOS has recorded any."""
    return run("/usr/bin/pmset", "-g", "therm", timeout=5) or "no thermal data recorded"


@mcp.tool(annotations=RO)
def idle_seconds() -> str:
    """How long since the last keyboard/mouse/trackpad input (no permission needed)."""
    out = run("/usr/sbin/ioreg", "-c", "IOHIDSystem", "-d", "4", timeout=5)
    m = re.search(r'"HIDIdleTime"\s*=\s*(\d+)', out)
    if not m:
        return "unavailable"
    secs = int(m.group(1)) / 1e9
    return f"{secs:.0f}s idle" if secs < 3600 else f"{secs / 3600:.1f}h idle"


@mcp.tool(annotations=RO)
def recent_files(hours: int = 24, limit: int = 30) -> str:
    """Files under your home directory that Spotlight has recorded as recently
    used (kMDItemLastUsedDate), excluding ~/Library (mostly app-internal noise,
    not things you were "working on"). File NAMES can reveal what you're
    working on, so this stays a private (non-shareable) result like every
    other tool here."""
    hours = max(1, min(int(hours), 168))
    limit = max(1, min(int(limit), 100))
    home = os.path.expanduser("~")
    out = run("/usr/bin/mdfind", "-onlyin", home,
              f"kMDItemLastUsedDate >= $time.now(-{hours * 3600})", timeout=8)
    rows = [l for l in out.splitlines() if l and not l.startswith(home + "/Library")]
    rows = [l.replace(home, "~") for l in rows[:limit]]
    return "\n".join(rows) if rows else f"no recently-used files found in the last {hours}h (or Spotlight indexing is off for this volume)"


@mcp.tool(annotations=RO)
def launch_agents() -> str:
    """What's running as a login item / background service (launchd), and
    what auto-starts from ~/Library/LaunchAgents or /Library/LaunchAgents."""
    running = run("/bin/launchctl", "list", timeout=5)
    user_agents = run("/bin/ls", os.path.expanduser("~/Library/LaunchAgents"), timeout=3)
    sys_agents = run("/bin/ls", "/Library/LaunchAgents", timeout=3)
    lines = [l for l in running.splitlines()[1:] if l and not re.match(r"^-?\d*\s+0\s+com\.apple\.", l)]
    return (f"non-Apple running services ({len(lines)} shown, max 25):\n" + "\n".join(lines[:25]) +
            f"\n\nauto-start on login (~/Library/LaunchAgents): {user_agents or '(none)'}"
            f"\nauto-start for all users (/Library/LaunchAgents): {sys_agents or '(none)'}")


@mcp.tool(annotations=RO)
def software_updates() -> str:
    """Recent macOS/App Store software update history."""
    out = run("/usr/sbin/softwareupdate", "--history", timeout=10)
    return out or "no update history available"


@mcp.tool(annotations=RO)
def crash_reports(days: int = 3) -> str:
    """Recent app crash reports (name + when), from ~/Library/Logs/DiagnosticReports.
    No Full Disk Access needed — this is the user's own log directory."""
    days = max(1, min(int(days), 30))
    d = os.path.expanduser("~/Library/Logs/DiagnosticReports")
    if not os.path.isdir(d):
        return "no diagnostic reports directory"
    cutoff = time.time() - days * 86400
    rows = []
    try:
        for name in os.listdir(d):
            if not name.endswith((".ips", ".crash")):
                continue
            p = os.path.join(d, name)
            try:
                mtime = os.path.getmtime(p)
            except OSError:
                continue
            if mtime >= cutoff:
                rows.append((mtime, name))
    except OSError:
        return "could not read diagnostic reports directory"
    rows.sort(reverse=True)
    if not rows:
        return f"no crash reports in the last {days} day(s) — good sign"
    return "\n".join(f"{time.strftime('%Y-%m-%d %H:%M', time.localtime(m))}  {n}" for m, n in rows[:30])


@mcp.tool(annotations=RO)
def bluetooth_devices() -> str:
    """Currently connected Bluetooth devices (name + type), if any."""
    out = run("/usr/sbin/system_profiler", "SPBluetoothDataType", "-json", timeout=10)
    try:
        import json
        data = json.loads(out)
    except (ValueError, TypeError):
        return "bluetooth info unavailable"
    names = []

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "device_connected" and isinstance(v, list):
                    for dev in v:
                        if isinstance(dev, dict):
                            names.extend(dev.keys())
                walk(v)
        elif isinstance(o, list):
            for x in o:
                walk(x)

    walk(data)
    return "connected: " + ", ".join(names[:20]) if names else "no connected Bluetooth devices found"


if __name__ == "__main__":
    mcp.run()
