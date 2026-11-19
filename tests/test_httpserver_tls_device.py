#!/usr/bin/env python3
"""Check the HTTP example over a verified TLS connection on a board."""

import argparse
import socket
import ssl
import time


def exchange(address, context, hostname, parts):
    with socket.create_connection(address, timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname=hostname) as secure:
            secure.settimeout(5)
            for part in parts:
                secure.sendall(part)
                if len(parts) > 1:
                    time.sleep(0.02)
            response = bytearray()
            while True:
                chunk = secure.recv(4096)
                if not chunk:
                    return bytes(response)
                response.extend(chunk)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ip", help="board IPv4 address")
    parser.add_argument("certificate", help="trusted test certificate PEM")
    parser.add_argument("--hostname", default="blitzmax-test.local")
    parser.add_argument("--port", type=int, default=8443)
    args = parser.parse_args()
    context = ssl.create_default_context(cafile=args.certificate)
    address = (args.ip, args.port)

    status = exchange(address, context, args.hostname,
        [b"GET /status HTTP/1.1\r\nHost: blitzmax-test.local\r\n\r\n"])
    assert b"200 OK" in status and b'"status":"ok"' in status, status

    echo = exchange(address, context, args.hostname, [
        b"POST /echo HTTP/1.1\r\nHost: blitzmax-test.local\r\n",
        b"Content-Length: 11\r\n\r\nhello ",
        b"world",
    ])
    assert b"200 OK" in echo and echo.endswith(b"hello world"), echo

    missing = exchange(address, context, args.hostname,
        [b"GET /missing HTTP/1.1\r\nHost: blitzmax-test.local\r\n\r\n"])
    assert b"404 Not Found" in missing, missing
    print("Verified HTTPS handshake, GET, fragmented POST, and 404 response")


if __name__ == "__main__":
    main()
