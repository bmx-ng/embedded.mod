#!/usr/bin/env python3
"""Verify HTTPS server-sent events on an ESP32 or Pico W test image."""

import argparse
import socket
import ssl
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("certificate")
    parser.add_argument("--server-name", default="stream.embedded.local")
    args = parser.parse_args()
    context = ssl.create_default_context(cafile=args.certificate)

    for last_id in (b"", b"7"):
        raw = socket.create_connection((args.address, 8443), timeout=10)
        raw.settimeout(10)
        with context.wrap_socket(raw, server_hostname=args.server_name) as connection:
            with connection.makefile("rb") as stream:
                request = b"GET /events HTTP/1.1\r\nHost: device\r\nConnection: close\r\n"
                if last_id:
                    request += b"Last-Event-ID: " + last_id + b"\r\n"
                connection.sendall(request + b"\r\n")
                assert b"200 OK" in stream.readline()
                headers = {}
                while line := stream.readline():
                    if line == b"\r\n":
                        break
                    name, value = line.split(b":", 1)
                    headers[name.lower()] = value.strip()
                assert headers[b"content-type"] == b"text/event-stream; charset=utf-8"
                assert headers[b"cache-control"] == b"no-cache"
                assert headers[b"transfer-encoding"] == b"chunked"
                body = bytearray()
                while True:
                    size = int(stream.readline().strip(), 16)
                    if size == 0:
                        assert stream.read(2) == b"\r\n"
                        break
                    body.extend(stream.read(size))
                    assert stream.read(2) == b"\r\n"
                assert b"retry: 500\n\n" in body
                assert b"event: update\nid: 7\ndata: first\ndata: second\n\n" in body
                assert b"event: cursor\ndata: resume=" + last_id + b"\n\n" in body
                assert b":\n\n" in body
                assert b"data: later\n\n" in body
                assert stream.read(1) == b""
        time.sleep(0.2)

    print("Verified trusted HTTPS SSE events, heartbeat, completion and Last-Event-ID")


if __name__ == "__main__":
    main()
