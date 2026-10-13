#!/usr/bin/env python3
# Pearl power-key handler: toggle panel DPMS instead of powering off.
# The power key on pearl is exposed by mtk-spmi-keys (PMIC keys), not mtk-kpd.
import os, select, struct, subprocess, sys, time

EV_KEY = 1
KEY_POWER = 116
EVENT = struct.Struct('@llHHi')
DPMS = '/sys/class/drm/card0-DSI-1/dpms'
WLOpm = '/usr/bin/wlopm'
OUTPUT = 'DSI-1'
_last_toggle = 0.0
_ignore_until = 0.0
_boot_delta = None

def find_power_events():
    """Return event device paths that may deliver KEY_POWER."""
    candidates = []
    try:
        text = open('/proc/bus/input/devices', encoding='utf-8', errors='replace').read()
    except OSError:
        text = ''
    for block in text.split('\n\n'):
        lname = block.lower()
        if not any(n in lname for n in ('mtk-spmi-keys', 'mtk-pmic-keys', 'mtk-kpd')):
            continue
        for line in block.splitlines():
            if line.startswith('H: Handlers='):
                for tok in line.split():
                    if tok.startswith('event'):
                        candidates.append('/dev/input/' + tok)
    # de-dup, stable order
    out = []
    for c in candidates:
        if c not in out:
            out.append(c)
    if not out:
        out = ['/dev/input/event2', '/dev/input/event0']
    return out

def wayland_env():
    env = dict(os.environ)
    env['XDG_RUNTIME_DIR'] = '/run/user/1000'
    try:
        names = [n for n in os.listdir('/run/user/1000')
                 if n.startswith('wayland-') and not n.endswith('.lock')]
        if names:
            env['WAYLAND_DISPLAY'] = sorted(names)[0]
    except OSError:
        pass
    return env

def toggle():
    global _last_toggle
    now = time.monotonic()
    if now < _ignore_until:
        return
    if now - _last_toggle < 1.0:
        return
    _last_toggle = now
    try:
        state = open(DPMS).read().strip()
    except OSError:
        state = 'On'
    action = '--off' if state == 'On' else '--on'
    print('pearl-powerkey: %s -> %s %s' % (state, action, OUTPUT), flush=True)
    if action == '--on':
        import glob
        for g in glob.glob('/sys/devices/system/cpu/cpufreq/policy*/scaling_governor'):
            try:
                open(g, 'w').write('schedutil\n')
            except OSError:
                pass
    subprocess.run([WLOpm, action, OUTPUT], env=wayland_env(), check=False)

def main():
    paths = find_power_events()
    fds = {}
    for p in paths:
        try:
            fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
            fds[fd] = p
        except OSError as exc:
            print('pearl-powerkey: cannot open %s: %r' % (p, exc), flush=True)
    if not fds:
        raise SystemExit('pearl-powerkey: no event device')
    print('pearl-powerkey: listening on %s' % ', '.join(fds.values()), flush=True)
    global _ignore_until, _boot_delta
    while True:
        try:
            bt = time.clock_gettime(time.CLOCK_BOOTTIME)
            mt = time.clock_gettime(time.CLOCK_MONOTONIC)
            delta = bt - mt
            if _boot_delta is not None and delta - _boot_delta > 1.0:
                _ignore_until = mt + 4.0
            _boot_delta = delta
        except (AttributeError, OSError):
            pass
        ready, _, _ = select.select(list(fds.keys()), [], [], 1.0)
        for fd in ready:
            try:
                data = os.read(fd, EVENT.size * 64)
            except OSError:
                continue
            for off in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _sec, _usec, typ, code, val = EVENT.unpack(data[off:off + EVENT.size])
                if typ == EV_KEY and code == KEY_POWER and val == 1:
                        try:
                            toggle()
                        except Exception as exc:
                            print('pearl-powerkey: error %r' % (exc,), flush=True)

if __name__ == '__main__':
    if '--toggle' in sys.argv:
        toggle()
    else:
        main()
