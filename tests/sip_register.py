#!/usr/bin/env python3
"""A tiny SIP phone for tests (Python standard library only).

It REGISTERs one extension with MD5 digest authentication. By default it exits
right after the answer: status 0 for 200 OK, 1 when the server refuses, 2 on a
network error. With --stay it keeps the registration alive and answers the
server's OPTIONS "qualify" pings, so Asterisk sees the phone as reachable.

    sip_register.py --user 101 --password secret [--server 127.0.0.1:5060] [--stay]
"""
import argparse
import hashlib
import random
import re
import socket
import string
import sys
import time


def md5(text):
    return hashlib.md5(text.encode()).hexdigest()


def rand(n=10):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def register_request(args, cseq, call_id, tag, auth=None):
    lines = [
        f"REGISTER sip:{args.server} SIP/2.0",
        f"Via: SIP/2.0/UDP 127.0.0.1:{args.port};branch=z9hG4bK{rand()};rport",
        "Max-Forwards: 70",
        f"From: <sip:{args.user}@{args.server}>;tag={tag}",
        f"To: <sip:{args.user}@{args.server}>",
        f"Call-ID: {call_id}",
        f"CSeq: {cseq} REGISTER",
        f"Contact: <sip:{args.user}@127.0.0.1:{args.port}>",
        f"Expires: {args.expires}",
        "User-Agent: sip_register/1.0",
    ]
    if auth:
        lines.append(auth)
    return ("\r\n".join(lines + ["Content-Length: 0", "", ""])).encode()


def authorization(args, challenge):
    realm = re.search(r'realm="([^"]+)"', challenge).group(1)
    nonce = re.search(r'nonce="([^"]+)"', challenge).group(1)
    uri = f"sip:{args.server}"
    response = md5(f"{md5(f'{args.user}:{realm}:{args.password}')}:{nonce}:{md5(f'REGISTER:{uri}')}")
    return (f'Authorization: Digest username="{args.user}", realm="{realm}", nonce="{nonce}", '
            f'uri="{uri}", response="{response}", algorithm=MD5')


def parse(data):
    text = data.decode(errors="replace")
    head = text.split("\r\n\r\n", 1)[0].split("\r\n")
    headers = {}
    for line in head[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            headers.setdefault(key.strip().lower(), []).append(value.strip())
    return head[0], headers


def answer(sock):
    """Wait for the next SIP *response*. Requests that arrive meanwhile (Asterisk
    qualifies a new contact with OPTIONS, sometimes before it answers the
    REGISTER) are answered with 200 OK and skipped."""
    while True:
        data, addr = sock.recvfrom(65535)
        if data.startswith(b"SIP/2.0"):
            return parse(data)
        if data.startswith(b"OPTIONS "):
            answer_options(sock, data, addr)


def register(sock, args, server):
    """One REGISTER exchange, answering a digest challenge. Returns the final status line."""
    call_id, tag = f"{rand(16)}@sip_register", rand(8)
    sock.sendto(register_request(args, 1, call_id, tag), server)
    first, headers = answer(sock)
    if " 401 " in first or " 407 " in first:
        challenges = headers.get("www-authenticate", []) + headers.get("proxy-authenticate", [])
        challenge = next((c for c in challenges if "sha" not in c.lower()), challenges[0])
        sock.sendto(register_request(args, 2, call_id, tag, authorization(args, challenge)), server)
        first, _ = answer(sock)
    return first


def answer_options(sock, data, addr):
    _, h = parse(data)
    to = h.get("to", [""])[0]
    if "tag=" not in to:
        to += f";tag={rand(8)}"
    reply = "\r\n".join([
        "SIP/2.0 200 OK",
        *[f"Via: {v}" for v in h.get("via", [])],
        f"From: {h.get('from', [''])[0]}",
        f"To: {to}",
        f"Call-ID: {h.get('call-id', [''])[0]}",
        f"CSeq: {h.get('cseq', [''])[0]}",
        "Allow: OPTIONS, INVITE, ACK, BYE, CANCEL",
        "Content-Length: 0", "", "",
    ])
    sock.sendto(reply.encode(), addr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--server", default="127.0.0.1:5060")
    ap.add_argument("--port", type=int, default=0, help="local UDP port (0 = any)")
    ap.add_argument("--expires", type=int, default=60)
    ap.add_argument("--stay", action="store_true", help="stay registered and answer OPTIONS until killed")
    args = ap.parse_args()

    host, port = args.server.rsplit(":", 1)
    server = (host, int(port))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", args.port))
    args.port = sock.getsockname()[1]
    sock.settimeout(5)
    try:
        status = register(sock, args, server)
        print(status, flush=True)
        if " 200 " not in status:
            return 1
        if not args.stay:
            return 0
        refresh_at = time.time() + args.expires / 2
        while True:
            try:
                data, addr = sock.recvfrom(65535)
            except socket.timeout:
                data = None
            if data and data.startswith(b"OPTIONS "):
                answer_options(sock, data, addr)
            if time.time() >= refresh_at:
                register(sock, args, server)
                refresh_at = time.time() + args.expires / 2
    except OSError as err:
        print(f"network error: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
