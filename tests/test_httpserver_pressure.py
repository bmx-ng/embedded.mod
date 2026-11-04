#!/usr/bin/env python3
"""Exercise four concurrent maximum-size HTTP requests on a device."""

import argparse
import hashlib
import socket
import threading
import time
from concurrent.futures import ThreadPoolExecutor


def exchange(host, port, request):
    with socket.create_connection((host, port), timeout=8) as connection:
        connection.settimeout(10)
        connection.sendall(request)
        result = bytearray()
        while part := connection.recv(4096):
            result.extend(part)
    return bytes(result)


def concurrent_echo(host, port, barrier, index):
    body = bytes((65 + index,)) * 8192
    header = (
        b"POST /echo HTTP/1.1\r\nHost: device\r\n"
        + b"X-Pad: " + b"a" * 4000 + b"\r\n"
        + b"Content-Length: 8192\r\n\r\n"
    )
    with socket.create_connection((host, port), timeout=8) as connection:
        connection.settimeout(12)
        connection.sendall(header + body[:256])
        barrier.wait(timeout=10)
        for offset in range(256, len(body), 1024):
            connection.sendall(body[offset:offset + 1024])
            time.sleep(0.01)
        result = bytearray()
        while part := connection.recv(4096):
            result.extend(part)
    status, separator, response_body = bytes(result).partition(b"\r\n\r\n")
    assert separator and b"200 OK" in status, (index, status[:100])
    assert response_body == body, (index, len(response_body))


def interrupted_body(host, port):
    with socket.create_connection((host, port), timeout=8) as connection:
        connection.sendall(
            b"POST /echo HTTP/1.1\r\nHost: device\r\n"
            b"Content-Length: 8192\r\n\r\nx"
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--rounds", type=int, default=10)
    parser.add_argument("--clients", type=int, default=4)
    parser.add_argument("--static-path")
    parser.add_argument("--static-sha256")
    args = parser.parse_args()
    assert args.rounds > 0
    assert 1 <= args.clients <= 4
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=args.clients) as pool:
        for round_number in range(args.rounds):
            barrier = threading.Barrier(args.clients)
            jobs = [pool.submit(concurrent_echo, args.host, args.port, barrier, i)
                    for i in range(args.clients)]
            for job in jobs:
                job.result()
            if (round_number + 1) % 5 == 0:
                print(f"{round_number + 1} concurrent rounds passed", flush=True)
        jobs = [pool.submit(interrupted_body, args.host, args.port)
                for _ in range(args.clients)]
        for job in jobs:
            job.result()
    time.sleep(0.2)
    status = exchange(args.host, args.port,
                      b"GET /status HTTP/1.1\r\nHost: device\r\n\r\n")
    assert b"200 OK" in status and b'"status":"ok"' in status
    if args.static_path or args.static_sha256:
        assert args.static_path and args.static_sha256
        request = (f"GET {args.static_path} HTTP/1.1\r\n"
                   "Host: device\r\n\r\n").encode("ascii")
        result = exchange(args.host, args.port, request)
        headers, separator, body = result.partition(b"\r\n\r\n")
        assert separator and b"200 OK" in headers
        assert hashlib.sha256(body).hexdigest() == args.static_sha256.lower()
    print(f"PASS: {args.rounds * args.clients} maximum-size concurrent requests, "
          f"{args.clients} interrupted bodies, recovery in {time.monotonic() - start:.1f}s")


if __name__ == "__main__":
    main()
