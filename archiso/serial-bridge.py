"""Ponte com a serial da VM de teste (QEMU -serial tcp:127.0.0.1:PORTA,server,nowait).

    python serial-bridge.py [porta] [arquivo-log] [arquivo-entrada]

Tudo que a VM escreve na serial vai pro arquivo de log. Tudo que for gravado no arquivo de
entrada e mandado pra VM (e o arquivo e esvaziado). Assim da pra dirigir o live ISO sem
depender da tela: com `console=ttyS0` na linha do kernel o systemd abre um login na serial.
"""
import os
import socket
import sys
import time

port = int(sys.argv[1]) if len(sys.argv) > 1 else 4446
log_path = sys.argv[2] if len(sys.argv) > 2 else 'serial.log'
in_path = sys.argv[3] if len(sys.argv) > 3 else 'serial-in.txt'

while True:
    try:
        s = socket.create_connection(('127.0.0.1', port), timeout=5)
        break
    except OSError:
        time.sleep(1)
s.settimeout(0.2)
with open(log_path, 'ab', buffering=0) as log:
    while True:
        try:
            data = s.recv(65536)
            if not data:
                break
            log.write(data)
        except socket.timeout:
            pass
        except OSError:
            break
        if os.path.exists(in_path) and os.path.getsize(in_path) > 0:
            with open(in_path, 'rb') as f:
                payload = f.read()
            open(in_path, 'wb').close()
            for ch in payload:
                s.sendall(bytes([ch]))
                time.sleep(0.02)
