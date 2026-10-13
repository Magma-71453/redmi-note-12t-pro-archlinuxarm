#!/usr/bin/env python3
# Pearl power-key handler: toggle panel DPMS instead of powering off.
import os, struct, subprocess, sys, time

EV_KEY = 1
KEY_POWER = 116
EVENT = struct.Struct('@llHHi')
DPMS = '/sys/class/drm/card0-DSI-1/dpms'
WLOpm = '/usr/bin/wlopm'
OUTPUT = 'DSI-1'

def find_power_event():
    try:
        text = open('/proc/bus/input/devices', encoding='utf-8', errors='replace').read()
    except OSError:
        return '/dev/input/event0'
    for block in text.split('\n\n'):
        if 'mtk-kpd' in block:
            for line in block.splitlines():
                if line.startswith('H: Handlers='):
                    for tok in line.split():
                        if tok.startswith('event'):
                            return '/dev/input/' + tok
    return '/dev/input/event0'

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
    try:
        state = open(DPMS).read().strip()
    except OSError:
        state = 'On'
    action = '--off' if state == 'On' else '--on'
    print('pearl-powerkey: %s -> %s %s' % (state, action, OUTPUT), flush=True)
    subprocess.run([WLOpm, action, OUTPUT], env=wayland_env(), check=False)

def main():
    dev = find_power_event()
    print('pearl-powerkey: listening on %s' % dev, flush=True)
    with open(dev, 'rb', buffering=0) as f:
        while True:
            data = f.read(EVENT.size)
            if not data:
                time.sleep(0.2)
                continue
            if len(data) < EVENT.size:
                continue
            _sec, _usec, typ, code, val = EVENT.unpack(data)
            if typ == EV_KEY and code == KEY_POWER and val == 1:
                try:
                    toggle()
                except Exception as exc:  # keep daemon alive
                    print('pearl-powerkey: error %r' % (exc,), flush=True)

if __name__ == '__main__':
    if '--toggle' in sys.argv:
        toggle()
    else:
        main()
