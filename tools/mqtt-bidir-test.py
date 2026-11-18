#!/usr/bin/env python3
# 10-minute bidirectional test: LED/IR-cut commands every ~10 s plus events.
# Writes /tmp/bidir_test.log: time, command, latency; events separately.
import socket, struct, time, os, sys

HOST = "127.0.0.1"
PORT = 1883
U = os.environ["MQTT_USER"].encode()
P = os.environ["MQTT_PASSWORD"].encode()
LOG = "/tmp/bidir_test.log"
DURATION = 600

def enc_len(n):
    out = b""
    while True:
        d = n % 128
        n //= 128
        if n:
            d |= 0x80
        out += bytes([d])
        if not n:
            return out

def sstr(b):
    return struct.pack(">H", len(b)) + b

def read_packet(s):
    h = s.recv(1)
    if not h:
        raise EOFError
    mult = 1
    ln = 0
    while True:
        b = s.recv(1)[0]
        ln += (b & 0x7f) * mult
        mult *= 128
        if not b & 0x80:
            break
    body = b""
    while len(body) < ln:
        d = s.recv(ln - len(body))
        if not d:
            raise EOFError
        body += d
    return bytes([h[0]]) + enc_len(ln) + body

def body_of(p):
    i = 1
    ln = 0
    mult = 1
    while True:
        b = p[i]
        i += 1
        ln += (b & 0x7f) * mult
        mult *= 128
        if not b & 0x80:
            break
    return p[i:]

def connect():
    s = socket.create_connection((HOST, PORT), timeout=5)
    vh = sstr(b"MQTT") + bytes([4, 0xC2]) + struct.pack(">H", 60)
    import random
    payload = sstr(("bidir_%d" % (os.getpid() % 100000)).encode()) + sstr(U) + sstr(P)
    s.sendall(bytes([0x10]) + enc_len(len(vh) + len(payload)) + vh + payload)
    ack = read_packet(s)
    assert ack[0] == 0x20 and body_of(ack)[1] == 0, ack
    return s

_pid = [0]
def subscribe(s, topic):
    t = topic.encode()
    _pid[0] += 1
    s.sendall(bytes([0x82]) + enc_len(2 + 2 + len(t) + 1) + struct.pack(">H", _pid[0]) + sstr(t) + b"\x00")

def publish(s, topic, payload):
    t = topic.encode()
    pl = payload.encode()
    s.sendall(bytes([0x30]) + enc_len(2 + len(t) + len(pl)) + sstr(t) + pl)

state = {}
events = []

def pump(s, timeout):
    s.settimeout(timeout)
    try:
        p = read_packet(s)
    except socket.timeout:
        return False
    except (EOFError, OSError):
        raise
    if p[0] >> 4 == 3:
        b = body_of(p)
        tl = (b[0] << 8) | b[1]
        topic = b[2:2 + tl].decode(errors="replace")
        pl = b[2 + tl:].decode(errors="replace")
        leaf = topic.split("/")[1] if (topic.startswith("doorbell3s/") and topic.count("/") == 1) else ""
        if leaf in ("ring", "tamper", "motion", "motion_end"):
            events.append((time.time(), leaf, pl))
        else:
            state[topic] = pl
    return True

def wait_state(s, topic, want, timeout, t0):
    end = t0 + timeout
    while time.time() < end:
        if state.get(topic) == want:
            return time.time() - t0
        pump(s, max(0.005, end - time.time()))
    return None

def main():
    f = open(LOG, "w", buffering=1)
    s = connect()
    for t in ("doorbell3s/led", "doorbell3s/ircut", "doorbell3s/ring",
              "doorbell3s/tamper", "doorbell3s/motion", "doorbell3s/motion_end",
              "doorbell3s/availability"):
        subscribe(s, t)
    t_start = time.time()
    while time.time() - t_start < 0.8:
        pump(s, 0.1)
    f.write("start %s retained=%s\n" % (time.strftime("%H:%M:%S"), state))
    lats = []
    gaps = []
    i = 0
    while time.time() - t_start < DURATION:
        # LED: alternate ON/OFF
        target = "ON" if i % 2 == 0 else "OFF"
        want = '{"on":%d}' % (1 if target == "ON" else 0)
        t0 = time.time()
        publish(s, "doorbell3s/led/set", target)
        d = wait_state(s, "doorbell3s/led", want, 30, t0)
        ts = time.strftime("%H:%M:%S", time.localtime(t0))
        f.write("cmd %s led %-3s -> %s\n" % (ts, target, ("%.0f ms" % (d * 1000)) if d else "TIMEOUT>30s"))
        if d is not None:
            lats.append(d)
            if d > 1.0:
                gaps.append((ts, "led", d))
        # IR-cut: alternate on/off
        itarget = "on" if i % 2 == 0 else "off"
        iwant = '{"mode":"%s"}' % itarget
        t0 = time.time()
        publish(s, "doorbell3s/ircut/set", itarget)
        d = wait_state(s, "doorbell3s/ircut", iwant, 30, t0)
        ts = time.strftime("%H:%M:%S", time.localtime(t0))
        f.write("cmd %s ircut %-3s -> %s\n" % (ts, itarget, ("%.0f ms" % (d * 1000)) if d else "TIMEOUT>30s"))
        if d is not None:
            lats.append(d)
            if d > 1.0:
                gaps.append((ts, "ircut", d))
        i += 1
        # keep the ~10 s cadence
        while time.time() - t0 < 10.0 and time.time() - t_start < DURATION:
            pump(s, 0.2)
    f.write("\nSUMMARY cmds=%d ok=%d min=%.0fms avg=%.0fms max=%.0fms\n" % (
        i * 2, len(lats), min(lats) * 1000, sum(lats) / len(lats) * 1000, max(lats) * 1000))
    f.write("GAPS>1s: %s\n" % (gaps if gaps else "none"))
    f.write("EVENTS:\n")
    for et, leaf, pl in events:
        f.write("  %s %s %s\n" % (time.strftime("%H:%M:%S", time.localtime(et)), leaf, pl))
    f.write("done %s\n" % time.strftime("%H:%M:%S"))
    f.close()
    s.close()

if __name__ == "__main__":
    main()
