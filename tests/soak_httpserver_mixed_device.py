#!/usr/bin/env python3
"""Exercise HTTPS, SSE and WebSocket together on the mixed device image."""

import argparse
import socket
import ssl
import time

from soak_httpserver_ws_device import (SERVER_NAME, compress, decode, frame,
                                       next_data, open_session, read_frame)


def connection(address, context):
    raw = socket.create_connection((address, 8443), timeout=10)
    raw.settimeout(10)
    return context.wrap_socket(raw, server_hostname=SERVER_NAME)


def request(address, context, method, path, body=b""):
    with connection(address, context) as client:
        request_bytes = (method + b" " + path + b" HTTP/1.1\r\nHost: device\r\n"
                         b"Connection: close\r\nContent-Length: " +
                         str(len(body)).encode() + b"\r\n\r\n" + body)
        client.sendall(request_bytes)
        result = bytearray()
        while chunk := client.recv(4096):
            result.extend(chunk)
        headers, response_body = bytes(result).split(b"\r\n\r\n", 1)
        if b"200 OK" not in headers:
            raise AssertionError(f"Unexpected HTTP response: {headers!r}")
        return response_body


def read_chunk(stream):
    size_line = stream.readline()
    if not size_line:
        raise AssertionError("SSE stream ended unexpectedly")
    size = int(size_line.split(b";", 1)[0], 16)
    if not size:
        raise AssertionError("SSE stream completed unexpectedly")
    data = stream.read(size)
    if len(data) != size or stream.read(2) != b"\r\n":
        raise AssertionError("Broken SSE chunk")
    return data


def open_events(address, context):
    client = connection(address, context)
    stream = client.makefile("rb")
    client.sendall(b"GET /events HTTP/1.1\r\nHost: device\r\nConnection: close\r\n\r\n")
    if b"200 OK" not in stream.readline():
        raise AssertionError("SSE request failed")
    headers = bytearray()
    while line := stream.readline():
        if line == b"\r\n":
            break
        headers.extend(line)
    if b"text/event-stream" not in headers or b"chunked" not in headers:
        raise AssertionError("SSE response has wrong headers")
    if b"data: connected" not in read_chunk(stream):
        raise AssertionError("Missing first SSE event")
    return client, stream


def run(address, duration, live_clients, label):
    certificate = ssl.get_server_certificate((address, 8443), timeout=10)
    context = ssl.create_default_context(cadata=certificate)
    deadline = time.monotonic() + duration
    counts = {"cycles": 0, "http": 0, "sse": 0, "websocket": 0, "pings": 0}
    first_metrics = None
    last_metrics = None
    print(f"{label}: started with {live_clients} concurrent clients", flush=True)
    while time.monotonic() < deadline:
        events_client, events_stream = open_events(address, context)
        ws_client, ws_stream = open_session(address, context)
        try:
            for index in range(12):
                source = b"mixed-" + b"xy" * 40 + str(counts["websocket"]).encode()
                ws_client.sendall(frame(1, compress(source), compressed=True))
                first, payload = next_data(ws_client, ws_stream, counts)
                if first & 15 != 1 or decode(first, payload) != b"echo:" + source:
                    raise AssertionError("Mixed WebSocket echo mismatch")
                counts["websocket"] += 1
                event = read_chunk(events_stream)
                if b"data: tick " not in event and b":\n\n" not in event:
                    raise AssertionError(f"Unexpected SSE event: {event!r}")
                counts["sse"] += 1
                if live_clients >= 3:
                    if request(address, context, b"GET", b"/status") != b"ok":
                        raise AssertionError("Status response mismatch")
                    counts["http"] += 1
                    if index % 4 == 0:
                        body = b"body-" + str(counts["http"]).encode()
                        if request(address, context, b"POST", b"/echo", body) != body:
                            raise AssertionError("POST echo mismatch")
                        counts["http"] += 1
        finally:
            events_stream.close()
            events_client.close()
        if live_clients == 2:
            for index in range(12):
                if request(address, context, b"GET", b"/status") != b"ok":
                    raise AssertionError("Status response mismatch")
                counts["http"] += 1
        values = request(address, context, b"GET", b"/metrics")
        last_metrics = dict(part.split(b"=", 1) for part in values.split(b";"))
        if first_metrics is None:
            first_metrics = last_metrics
        if last_metrics[b"integrity"] != b"1":
            raise AssertionError("Managed heap integrity failed")
        if int(last_metrics[b"failures"]) > int(first_metrics[b"failures"]):
            raise AssertionError("Managed allocation failures increased")
        counts["http"] += 1
        ws_client.sendall(frame(8, (1000).to_bytes(2, "big")))
        if read_frame(ws_stream) != (0x88, (1000).to_bytes(2, "big")):
            raise AssertionError("WebSocket close mismatch")
        ws_stream.close()
        ws_client.close()
        counts["cycles"] += 1
        print(f"{label}: {counts}; reusable={last_metrics[b'reusable'].decode()}", flush=True)
    print(f"{label}: PASS after {duration}s; {counts}; "
          f"first_metrics={first_metrics}; last_metrics={last_metrics}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("--duration", type=int, default=300)
    parser.add_argument("--live-clients", type=int, choices=(2, 3), default=3)
    parser.add_argument("--label", default="device")
    args = parser.parse_args()
    run(args.address, args.duration, args.live_clients, args.label)


if __name__ == "__main__":
    main()
