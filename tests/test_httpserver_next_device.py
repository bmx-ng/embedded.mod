#!/usr/bin/env python3
"""Check optional connection reuse and chunked uploads on an HTTP device image."""

import argparse
import socket


def response(stream, body=True):
    status = stream.readline()
    assert status, "connection closed before response"
    headers = {}
    while line := stream.readline():
        if line == b"\r\n":
            break
        name, value = line.split(b":", 1)
        headers[name.lower()] = value.strip()
    payload = stream.read(int(headers[b"content-length"])) if body else b""
    return status, headers, payload


def check(ip, port):
    with socket.create_connection((ip, port), timeout=5) as sock:
        sock.settimeout(5)
        with sock.makefile("rb") as stream:
            sock.sendall(b"GET /status HTTP/1.1\r\nHost: device\r\n\r\n")
            status, headers, payload = response(stream)
            assert b"200 OK" in status and payload == b'{"status":"ok"}'
            assert headers[b"connection"] == b"keep-alive"

            sock.sendall(
                b"POST /echo HTTP/1.1\r\nHost: device\r\n"
                b"Transfer-Encoding: chunked\r\n\r\n"
            )
            for part in (b"5\r\nhe", b"llo\r", b"\n6\r\n world\r\n", b"0\r\n\r\n"):
                sock.sendall(part)
            status, headers, payload = response(stream)
            assert b"200 OK" in status and payload == b"hello world"
            assert headers[b"connection"] == b"keep-alive"

            body = bytes(range(256)) * 128
            sock.sendall(
                b"POST /upload HTTP/1.1\r\nHost: device\r\n"
                b"Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            )
            for start in range(0, len(body), 512):
                part = body[start:start + 512]
                sock.sendall(f"{len(part):x}\r\n".encode() + part + b"\r\n")
            sock.sendall(b"0\r\n\r\n")
            status, headers, payload = response(stream)
            assert b"200 OK" in status
            assert payload == f"{len(body)}:{sum(body) % 65521}".encode()
            assert headers[b"connection"] == b"close"
            assert stream.read(1) == b""

    with socket.create_connection((ip, port), timeout=5) as sock:
        sock.settimeout(5)
        with sock.makefile("rb") as stream:
            sock.sendall(
                b"POST /echo HTTP/1.1\r\nHost: device\r\n"
                b"Content-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n"
            )
            status, headers, _ = response(stream)
            assert b"400 Bad Request" in status and headers[b"connection"] == b"close"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ip", help="board IPv4 address")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    check(args.ip, args.port)
    print("Verified keep-alive, chunked echo, 32 KiB streamed upload, and framing rejection")
