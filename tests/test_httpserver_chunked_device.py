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

    def static_request(method, extra=b""):
        with connect() as connection, connection.makefile("rb") as stream:
            connection.sendall(method + b" /assets/range-fixture.txt HTTP/1.1\r\n"
                               b"Host: device\r\nConnection: close\r\n" + extra + b"\r\n")
            status, headers = read_head(stream)
            body = stream.read(int(headers[b"content-length"])) if method != b"HEAD" else b""
            return status, headers, body

    original = b"abcdef0123456789" * 256
    status, headers, body = static_request(b"GET")
    assert b"200 OK" in status
    assert body == original
    assert headers[b"accept-ranges"] == b"bytes"
    assert headers[b"cache-control"] == b"public, max-age=60"
    tag = headers[b"etag"]

    status, headers, body = static_request(b"GET", b"If-None-Match: " + tag + b"\r\n")
    assert b"304 Not Modified" in status
    assert body == b""

    status, headers, body = static_request(b"GET", b"Range: bytes=3-7\r\n")
    assert b"206 Partial Content" in status
    assert headers[b"content-range"] == b"bytes 3-7/4096"
    assert body == b"def01"

    status, headers, body = static_request(b"HEAD", b"Range: bytes=-5\r\n")
    assert b"206 Partial Content" in status
    assert headers[b"content-length"] == b"5"
    assert body == b""

    status, headers, body = static_request(b"GET", b"Range: bytes=5000-\r\n")
    assert b"416 Range Not Satisfiable" in status
    assert headers[b"content-range"] == b"bytes */4096"
    assert body == b""

    with connect() as connection, connection.makefile("rb") as stream:
        connection.sendall(b"GET /assets/second.key HTTP/1.1\r\n"
                           b"Host: device\r\nConnection: close\r\n\r\n")
        status, headers = read_head(stream)
        assert b"404 Not Found" in status

    print("Verified trusted TLS, chunked output, reuse, HEAD, HTTP/1.0, static ranges and cache")


if __name__ == "__main__":
    main()
