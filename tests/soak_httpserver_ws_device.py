#!/usr/bin/env python3
"""Soak an HTTPS WebSocket test image with verified TLS and repeated sessions."""

import argparse
import base64
import hashlib
import os
import socket
import ssl
import time
import zlib


SERVER_NAME = "stream.embedded.local"
GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def frame(opcode, payload=b"", *, final=True, compressed=False):
    first = opcode | (0x80 if final else 0) | (0x40 if compressed else 0)
    if len(payload) < 126:
        header = bytes((first, 0x80 | len(payload)))
    else:
        header = bytes((first, 0xfe)) + len(payload).to_bytes(2, "big")
    mask = os.urandom(4)
    return header + mask + bytes(value ^ mask[index % 4]
                                 for index, value in enumerate(payload))


def read_frame(stream):
    first = stream.read(1)
    if not first:
        raise AssertionError("WebSocket closed unexpectedly")
    second = stream.read(1)
    if not second or second[0] & 0x80:
        raise AssertionError("Missing or masked server frame")
    length = second[0] & 127
    if length == 126:
        length = int.from_bytes(stream.read(2), "big")
    elif length == 127:
        length = int.from_bytes(stream.read(8), "big")
    payload = stream.read(length)
    if len(payload) != length:
        raise AssertionError("Incomplete server frame")
    return first[0], payload


def next_data(connection, stream, counts):
    while True:
        first, payload = read_frame(stream)
        if first == 0x89:
            connection.sendall(frame(10, payload))
            counts["pings"] += 1
            continue
        if first & 15 == 8:
            code = int.from_bytes(payload[:2], "big") if len(payload) >= 2 else 0
            raise AssertionError(f"Unexpected close frame: {code}")
        return first, payload


def compress(payload):
    encoder = zlib.compressobj(wbits=-9)
    output = encoder.compress(payload) + encoder.flush(zlib.Z_SYNC_FLUSH)
    if not output.endswith(b"\x00\x00\xff\xff"):
        raise AssertionError("Incomplete deflate flush")
    return output[:-4]


def decode(first, payload):
    if first & 0x40:
        decoder = zlib.decompressobj(-9)
        return decoder.decompress(payload + b"\x00\x00\xff\xff")
    return payload


def open_session(address, context):
    raw = socket.create_connection((address, 8443), timeout=10)
    raw.settimeout(40)
    connection = context.wrap_socket(raw, server_hostname=SERVER_NAME)
    stream = connection.makefile("rb")
    key = base64.b64encode(os.urandom(16))
    request = (b"GET /ws HTTP/1.1\r\nHost: device\r\nConnection: Upgrade\r\n"
               b"Upgrade: websocket\r\nSec-WebSocket-Version: 13\r\n"
               b"Sec-WebSocket-Key: " + key + b"\r\n"
               b"Origin: https://device.test\r\n"
               b"Sec-WebSocket-Protocol: device.v1\r\n"
               b"Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n\r\n")
    connection.sendall(request)
    headers = bytearray()
    while not headers.endswith(b"\r\n\r\n"):
        byte = stream.read(1)
        if not byte or len(headers) >= 4096:
            raise AssertionError("WebSocket upgrade failed")
        headers.extend(byte)
    expected = base64.b64encode(hashlib.sha1(key + GUID).digest())
    if (b"101 Switching Protocols" not in headers or
            b"Sec-WebSocket-Accept: " + expected + b"\r\n" not in headers or
            b"Sec-WebSocket-Protocol: device.v1\r\n" not in headers or
            b"Sec-WebSocket-Extensions: permessage-deflate;" not in headers or
            b"client_max_window_bits=9" not in headers):
        raise AssertionError(f"Unexpected upgrade: {headers!r}")
    if read_frame(stream) != (0x81, b"ready"):
        raise AssertionError("Missing greeting")
    return connection, stream


def run(address, duration, idle_every, label, reconnect_delay_ms):
    # Pin the currently presented test certificate for subsequent verified TLS
    # connections. The first fetch is only a local test-image discovery step.
    certificate = ssl.get_server_certificate((address, 8443), timeout=10)
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(certificate)).hexdigest()[:16]
    context = ssl.create_default_context(cadata=certificate)
    deadline = time.monotonic() + duration
    counts = {"sessions": 0, "messages": 0, "pings": 0}
    print(f"{label}: started; TLS certificate SHA-256 {fingerprint}", flush=True)
    while time.monotonic() < deadline:
        connection, stream = open_session(address, context)
        try:
            for index in range(30):
                source = b"sample-" + b"ab" * 40 + str(counts["messages"]).encode()
                connection.sendall(frame(1, compress(source), compressed=True))
                first, payload = next_data(connection, stream, counts)
                if first & 15 != 1 or decode(first, payload) != b"echo:" + source:
                    raise AssertionError("Compressed text echo mismatch")
                counts["messages"] += 1

                binary = os.urandom(16)
                connection.sendall(frame(2, binary))
                first, payload = next_data(connection, stream, counts)
                if first & 15 != 2 or decode(first, payload) != binary:
                    raise AssertionError("Binary echo mismatch")
                counts["messages"] += 1

                if index % 10 == 0:
                    connection.sendall(frame(1, b"fragment-", final=False))
                    connection.sendall(frame(9, b"probe"))
                    if next_data(connection, stream, counts) != (0x8a, b"probe"):
                        raise AssertionError("Ping/pong mismatch")
                    connection.sendall(frame(0, b"message"))
                    first, payload = next_data(connection, stream, counts)
                    if first & 15 != 1 or decode(first, payload) != b"echo:fragment-message":
                        raise AssertionError("Fragmented echo mismatch")
                    counts["messages"] += 1

            if idle_every and counts["sessions"] % idle_every == 0:
                first, payload = read_frame(stream)
                if first != 0x89:
                    raise AssertionError(f"Expected idle ping, got {first:#x}")
                connection.sendall(frame(10, payload))
                counts["pings"] += 1
                connection.sendall(frame(1, b"after-idle"))
                if next_data(connection, stream, counts) != (0x81, b"echo:after-idle"):
                    raise AssertionError("Idle recovery mismatch")
                counts["messages"] += 1

            connection.sendall(frame(8, (1000).to_bytes(2, "big")))
            if read_frame(stream) != (0x88, (1000).to_bytes(2, "big")):
                raise AssertionError("Close handshake mismatch")
            if stream.read(1) != b"":
                raise AssertionError("WebSocket did not close after the close handshake")
        finally:
            stream.close()
            connection.close()
        counts["sessions"] += 1
        print(f"{label}: {counts['sessions']} sessions, {counts['messages']} messages, "
              f"{counts['pings']} idle pings", flush=True)
        if reconnect_delay_ms:
            time.sleep(reconnect_delay_ms / 1000)
    print(f"{label}: PASS after {duration}s; {counts}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("--duration", type=int, default=600)
    parser.add_argument("--idle-every", type=int, default=3)
    parser.add_argument("--reconnect-delay-ms", type=int, default=0)
    parser.add_argument("--label", default="device")
    args = parser.parse_args()
    if args.reconnect_delay_ms < 0:
        parser.error("--reconnect-delay-ms must be nonnegative")
    run(args.address, args.duration, args.idle_every, args.label,
        args.reconnect_delay_ms)


if __name__ == "__main__":
    main()
