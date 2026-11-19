#!/usr/bin/env python3
"""Verify trusted WSS upgrades and bounded frames on Pico W or ESP32."""

import argparse
import base64
import hashlib
import os
import socket
import ssl
import time
import zlib


def client_frame(opcode, payload=b"", fin=True, compressed=False):
    first = opcode | (0x80 if fin else 0) | (0x40 if compressed else 0)
    if len(payload) < 126:
        header = bytes((first, len(payload) | 0x80))
    else:
        header = bytes((first, 126 | 0x80)) + len(payload).to_bytes(2, "big")
    mask = os.urandom(4)
    return header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload))


def server_frame(stream):
    first = stream.read(1)
    assert first, "server closed before sending a frame"
    second = stream.read(1)[0]
    assert not second & 0x80, "server frame must be unmasked"
    size = second & 127
    if size == 126:
        size = int.from_bytes(stream.read(2), "big")
    elif size == 127:
        size = int.from_bytes(stream.read(8), "big")
    payload = stream.read(size)
    assert len(payload) == size
    return first[0], payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address")
    parser.add_argument("certificate")
    parser.add_argument("--server-name", default="stream.embedded.local")
    args = parser.parse_args()
    context = ssl.create_default_context(cafile=args.certificate)

    for _ in range(5):
        raw = socket.create_connection((args.address, 8443), timeout=10)
        raw.settimeout(10)
        with context.wrap_socket(raw, server_hostname=args.server_name) as connection:
            with connection.makefile("rb") as stream:
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
                    part = stream.read(1)
                    assert part, "server closed during WebSocket upgrade"
                    headers.extend(part)
                assert b"101 Switching Protocols" in headers
                expected = base64.b64encode(hashlib.sha1(
                    key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
                assert b"Sec-WebSocket-Accept: " + expected + b"\r\n" in headers
                assert b"Sec-WebSocket-Protocol: device.v1\r\n" in headers
                assert b"Sec-WebSocket-Extensions: permessage-deflate; server_no_context_takeover; client_no_context_takeover; server_max_window_bits=9; client_max_window_bits=9\r\n" in headers
                assert server_frame(stream) == (0x81, b"ready")
                connection.sendall(client_frame(1, b"hello ", fin=False))
                connection.sendall(client_frame(9, b"probe"))
                assert server_frame(stream) == (0x8a, b"probe")
                connection.sendall(client_frame(0, b"device"))
                assert server_frame(stream) == (0x81, b"echo:hello device")
                connection.sendall(client_frame(2, b"\x00\x80\xff"))
                assert server_frame(stream) == (0x82, b"\x00\x80\xff")
                source = b"x" * 100
                encoder = zlib.compressobj(wbits=-15)
                compressed = encoder.compress(source) + encoder.flush(zlib.Z_SYNC_FLUSH)
                connection.sendall(client_frame(1, compressed[:-4], compressed=True))
                first, payload = server_frame(stream)
                assert first == 0xc1, (first, payload)
                decoded = zlib.decompress(payload + b"\x00\x00\xff\xff\x01\x00\x00\xff\xff", -15)
                assert decoded == b"echo:" + source
                connection.sendall(client_frame(8, (1000).to_bytes(2, "big")))
                assert server_frame(stream) == (0x88, (1000).to_bytes(2, "big"))
                assert stream.read(1) == b""
        time.sleep(0.1)

    print("Verified five trusted WSS upgrades, subprotocols, deflate, fragmented text, ping/pong, binary echo and close")


if __name__ == "__main__":
    main()
