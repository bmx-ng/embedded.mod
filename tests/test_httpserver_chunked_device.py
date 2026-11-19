#!/usr/bin/env python3
"""Verify unknown-length HTTPS responses on an ESP32 or Pico W test image."""

import argparse
import socket
import ssl


def read_head(stream):
    status = stream.readline()
    if not status:
        raise AssertionError("connection closed before response")
    headers = {}
    while line := stream.readline():
        if line == b"\r\n":
            break
        name, value = line.split(b":", 1)
        headers[name.lower()] = value.strip()
    return status, headers


def read_chunked(stream):
    result = bytearray()
    while True:
        size = int(stream.readline().strip(), 16)
        if size == 0:
            assert stream.readline() == b"\r\n"
            return bytes(result)
        result.extend(stream.read(size))
        assert stream.read(2) == b"\r\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("certificate")
    parser.add_argument("--server-name", default="stream.embedded.local")
    args = parser.parse_args()
    context = ssl.create_default_context(cafile=args.certificate)

    def connect():
        raw = socket.create_connection((args.address, 8443), timeout=10)
        raw.settimeout(10)
        return context.wrap_socket(raw, server_hostname=args.server_name)

    with connect() as connection, connection.makefile("rb") as stream:
        connection.sendall(b"GET /generated HTTP/1.1\r\nHost: device\r\n\r\n")
        status, headers = read_head(stream)
        assert b"200 OK" in status
        assert headers[b"transfer-encoding"] == b"chunked"
        assert b"content-length" not in headers
        assert headers[b"connection"] == b"keep-alive"
        assert read_chunked(stream) == b"x" * 8193

        connection.sendall(b"HEAD /generated HTTP/1.1\r\nHost: device\r\n\r\n")
        status, headers = read_head(stream)
        assert b"200 OK" in status
        assert headers[b"transfer-encoding"] == b"chunked"

        connection.sendall(b"GET /no-body HTTP/1.1\r\nHost: device\r\n\r\n")
        status, headers = read_head(stream)
        assert b"204 No Content" in status
        assert headers[b"content-length"] == b"0"
        assert b"transfer-encoding" not in headers

        connection.sendall(b"GET /status HTTP/1.1\r\nHost: device\r\nConnection: close\r\n\r\n")
        status, headers = read_head(stream)
        assert b"200 OK" in status
        assert stream.read(int(headers[b"content-length"])) == b'{"status":"ok"}'
        assert stream.read(1) == b""

    with connect() as connection, connection.makefile("rb") as stream:
        connection.sendall(b"GET /generated HTTP/1.0\r\n\r\n")
        status, headers = read_head(stream)
        assert b"HTTP/1.0 200 OK" in status
        assert headers[b"connection"] == b"close"
        assert b"transfer-encoding" not in headers
        assert b"content-length" not in headers
        assert stream.read() == b"x" * 8193

    print("Verified trusted TLS, chunked response, reuse, HEAD, 204, and HTTP/1.0 fallback")


if __name__ == "__main__":
    main()
