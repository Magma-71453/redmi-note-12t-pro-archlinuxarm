#!/bin/sh
# Force a fresh KMS modeset after suspend/resume: the vendor DSI controller
# can otherwise stay in a white/underrun state that DPMS alone does not clear.
systemctl stop pearl-labwc.service 2>/dev/null
pkill -x pearl-panel 2>/dev/null
pkill -x wvkbd-mobintl 2>/dev/null
pkill -x kitty 2>/dev/null
pkill -x kitten 2>/dev/null
sleep 0.5
systemctl start pearl-labwc.service 2>/dev/null
