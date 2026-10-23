#!/usr/bin/env python3
import socket
import os
import sys
import time
import signal

running = True

def handle_sig(sig, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, handle_sig)
signal.signal(signal.SIGINT, handle_sig)

runtime = os.environ.get("XDG_RUNTIME_DIR")
sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
if not runtime or not sig:
    sys.exit(1)

sock_path = f"{runtime}/hypr/{sig}/.socket.sock"
last = ""

while running:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(sock_path)
        s.sendall(b"cursorpos")
        data = s.recv(64).decode("utf-8", "ignore").strip()
        s.close()
        if data and data != last:
            last = data
            parts = [v.strip() for v in data.split(",")]
            if len(parts) == 2:
                sys.stdout.write(f"{parts[0]} {parts[1]}\n")
                sys.stdout.flush()
    except Exception:
        pass
    time.sleep(0.008)
