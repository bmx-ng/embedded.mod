#!/usr/bin/env python3
"""Wire-level regressions for the shared embedded HTTP server on a host."""

import pathlib
import base64
import hashlib
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest


class HTTPServerWireTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        root = pathlib.Path(cls.temp.name)
        cls.root = root
        (root / "index.html").write_text("<h1>root</h1>", encoding="utf-8")
        (root / "large.txt").write_bytes(b"abcdef0123456789" * 256)
        (root / "huge.bin").write_bytes(b"h" * 70000)
        (root / "changing.txt").write_bytes(b"before")
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            cls.port = probe.getsockname()[1]
        cls.process = subprocess.Popen(
            [sys.argv[1], str(cls.port), str(root)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if cls.process.poll() is not None:
                raise RuntimeError(cls.process.stderr.read().decode())
            try:
                with socket.create_connection(("127.0.0.1", cls.port), timeout=0.2):
                    return
            except OSError:
                time.sleep(0.02)
        raise RuntimeError("server did not start")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait(timeout=3)
        cls.temp.cleanup()

    def exchange(self, *fragments):
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(3)
            close_header_added = False
            for fragment in fragments:
                if not close_header_added and b"\r\n\r\n" in fragment:
                    fragment = fragment.replace(b"\r\n\r\n", b"\r\nConnection: close\r\n\r\n", 1)
                    close_header_added = True
                sock.sendall(fragment)
                time.sleep(0.005)
            result = bytearray()
            while True:
                part = sock.recv(4096)
                if not part:
                    return bytes(result)
                result.extend(part)

    def test_get_and_head(self):
        get = self.exchange(b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertIn(b"200 OK", get)
        self.assertTrue(get.endswith(b'{"status":"ok"}'))
        head = self.exchange(b"HEAD /status HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertIn(b"Content-Length: 15\r\n", head)
        self.assertTrue(head.endswith(b"\r\n\r\n"))
        missing = self.exchange(b"HEAD /missing HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertIn(b"404 Not Found", missing)
        self.assertTrue(missing.endswith(b"\r\n\r\n"))

    def test_unknown_length_response_framing(self):
        def closed_count():
            result = self.exchange(b"GET /producer-closed HTTP/1.1\r\nHost: local\r\n\r\n")
            return int(result.split(b"\r\n\r\n", 1)[1])

        before = closed_count()

        def decode_chunks(data):
            parts = []
            while True:
                line, data = data.split(b"\r\n", 1)
                size = int(line, 16)
                if size == 0:
                    self.assertEqual(data, b"\r\n")
                    return b"".join(parts)
                self.assertEqual(data[size:size + 2], b"\r\n")
                parts.append(data[:size])
                data = data[size + 2:]

        generated = self.exchange(b"GET /generated HTTP/1.1\r\nHost: local\r\n\r\n")
        headers, body = generated.split(b"\r\n\r\n", 1)
        self.assertIn(b"Transfer-Encoding: chunked", headers)
        self.assertNotIn(b"Content-Length:", headers)
        self.assertEqual(decode_chunks(body), b"x" * 4097)

        file_response = self.exchange(b"GET /unknown-file HTTP/1.1\r\nHost: local\r\n\r\n")
        headers, body = file_response.split(b"\r\n\r\n", 1)
        self.assertIn(b"Transfer-Encoding: chunked", headers)
        self.assertEqual(decode_chunks(body), b"abcdef0123456789" * 256)

        empty = self.exchange(b"GET /empty-generated HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertEqual(empty.split(b"\r\n\r\n", 1)[1], b"0\r\n\r\n")

        old_http = self.exchange(b"GET /generated HTTP/1.0\r\n\r\n")
        headers, body = old_http.split(b"\r\n\r\n", 1)
        self.assertIn(b"HTTP/1.0 200", headers)
        self.assertIn(b"Connection: close", headers)
        self.assertNotIn(b"Transfer-Encoding:", headers)
        self.assertNotIn(b"Content-Length:", headers)
        self.assertEqual(body, b"x" * 4097)

        head = self.exchange(b"HEAD /generated HTTP/1.1\r\nHost: local\r\n\r\n")
        headers, body = head.split(b"\r\n\r\n", 1)
        self.assertIn(b"Transfer-Encoding: chunked", headers)
        self.assertEqual(body, b"")

        no_body = self.exchange(b"GET /no-body-generated HTTP/1.1\r\nHost: local\r\n\r\n")
        headers, body = no_body.split(b"\r\n\r\n", 1)
        self.assertIn(b"204 No Content", headers)
        self.assertIn(b"Content-Length: 0", headers)
        self.assertNotIn(b"Transfer-Encoding:", headers)
        self.assertEqual(body, b"")
        self.assertEqual(closed_count() - before, 5)

    def test_chunked_response_keep_alive(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(3)
            with sock.makefile("rb") as stream:
                sock.sendall(b"GET /generated HTTP/1.1\r\nHost: local\r\n\r\n")
                self.assertIn(b"200 OK", stream.readline())
                headers = {}
                while line := stream.readline():
                    if line == b"\r\n":
                        break
                    name, value = line.split(b":", 1)
                    headers[name.lower()] = value.strip()
                self.assertEqual(headers[b"transfer-encoding"], b"chunked")
                self.assertEqual(headers[b"connection"], b"keep-alive")
                result = bytearray()
                while True:
                    size = int(stream.readline().strip(), 16)
                    if size == 0:
                        self.assertEqual(stream.readline(), b"\r\n")
                        break
                    result.extend(stream.read(size))
                    self.assertEqual(stream.read(2), b"\r\n")
                self.assertEqual(result, b"x" * 4097)
                sock.sendall(b"GET /status HTTP/1.1\r\nHost: local\r\nConnection: close\r\n\r\n")
                self.assertIn(b"200 OK", stream.readline())
                headers = {}
                while line := stream.readline():
                    if line == b"\r\n":
                        break
                    name, value = line.split(b":", 1)
                    headers[name.lower()] = value.strip()
                self.assertEqual(stream.read(int(headers[b"content-length"])), b'{"status":"ok"}')
                self.assertEqual(stream.read(1), b"")

    def test_server_sent_events_stream(self):
        def read_chunk(stream):
            size = int(stream.readline().strip(), 16)
            if size == 0:
                self.assertEqual(stream.read(2), b"\r\n")
                return b""
            data = stream.read(size)
            self.assertEqual(stream.read(2), b"\r\n")
            return data

        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(3)
            with sock.makefile("rb") as stream:
                sock.sendall(b"GET /events HTTP/1.1\r\nHost: local\r\n\r\n")
                self.assertIn(b"200 OK", stream.readline())
                headers = {}
                while line := stream.readline():
                    if line == b"\r\n":
                        break
                    name, value = line.split(b":", 1)
                    headers[name.lower()] = value.strip()
                self.assertEqual(headers[b"content-type"], b"text/event-stream; charset=utf-8")
                self.assertEqual(headers[b"cache-control"], b"no-cache")
                self.assertEqual(headers[b"transfer-encoding"], b"chunked")
                self.assertEqual(read_chunk(stream),
                                 b"event: update\nid: 42\ndata: first\ndata: second\n\n"
                                 b"retry: 750\n\n")

                queued = self.exchange(b"GET /events-send HTTP/1.1\r\nHost: local\r\n\r\n")
                self.assertTrue(queued.endswith(b"queued"))
                while (chunk := read_chunk(stream)) == b":\n\n":
                    pass
                self.assertEqual(chunk, b"data: later\n\n: note\n\n")
                self.assertEqual(read_chunk(stream), b":\n\n")

                finished = self.exchange(b"GET /events-finish HTTP/1.1\r\nHost: local\r\n\r\n")
                self.assertTrue(finished.endswith(b"finished"))
                self.assertEqual(read_chunk(stream), b"")

        state = self.exchange(b"GET /events-state HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertTrue(state.endswith(b"1:"))

        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(3)
            with sock.makefile("rb") as stream:
                sock.sendall(b"GET /events HTTP/1.1\r\nHost: local\r\n"
                             b"Last-Event-ID: 42\r\n\r\n")
                self.assertIn(b"200 OK", stream.readline())
                while stream.readline() != b"\r\n":
                    pass
                self.assertIn(b"event: update", read_chunk(stream))
                state = self.exchange(b"GET /events-state HTTP/1.1\r\nHost: local\r\n\r\n")
                self.assertTrue(state.endswith(b"0:42"))
                self.exchange(b"GET /events-finish HTTP/1.1\r\nHost: local\r\n\r\n")
                self.assertEqual(read_chunk(stream), b"")

    def test_websocket_upgrade_frames_and_errors(self):
        def client_frame(opcode, payload=b"", fin=True, masked=True):
            first = opcode | (0x80 if fin else 0)
            if len(payload) < 126:
                header = bytes((first, len(payload) | (0x80 if masked else 0)))
            else:
                header = bytes((first, 126 | (0x80 if masked else 0))) + len(payload).to_bytes(2, "big")
            if not masked:
                return header + payload
            mask = os.urandom(4)
            return header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload))

        def server_frame(stream):
            first = stream.read(1)
            self.assertTrue(first)
            second = stream.read(1)[0]
            self.assertEqual(second & 0x80, 0)
            size = second & 127
            if size == 126:
                size = int.from_bytes(stream.read(2), "big")
            elif size == 127:
                size = int.from_bytes(stream.read(8), "big")
            return first[0] & 15, stream.read(size)

        key = b"dGhlIHNhbXBsZSBub25jZQ=="
        request = (b"GET /ws HTTP/1.1\r\nHost: local\r\nConnection: Upgrade\r\n"
                   b"Upgrade: websocket\r\nSec-WebSocket-Version: 13\r\n"
                   b"Sec-WebSocket-Key: " + key + b"\r\nOrigin: https://local.test\r\n\r\n")
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(3)
            with sock.makefile("rb") as stream:
                sock.sendall(request)
                headers = bytearray()
                while not headers.endswith(b"\r\n\r\n"):
                    headers.extend(stream.read(1))
                self.assertIn(b"101 Switching Protocols", headers)
                self.assertIn(b"Connection: Upgrade\r\n", headers)
                expected = base64.b64encode(hashlib.sha1(
                    key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
                self.assertIn(b"Sec-WebSocket-Accept: " + expected + b"\r\n", headers)
                self.assertEqual(server_frame(stream), (1, b"ready"))
                sock.sendall(client_frame(1, b"hel", fin=False))
                sock.sendall(client_frame(9, b"check"))
                self.assertEqual(server_frame(stream), (10, b"check"))
                sock.sendall(client_frame(0, b"lo"))
                self.assertEqual(server_frame(stream), (1, b"echo:hello"))
                sock.sendall(client_frame(2, b"\x00\x01\xff"))
                self.assertEqual(server_frame(stream), (2, b"\x00\x01\xff"))
                sock.sendall(client_frame(1, b"unmasked", masked=False))
                opcode, payload = server_frame(stream)
                self.assertEqual(opcode, 8)
                self.assertEqual(payload[:2], (1002).to_bytes(2, "big"))
                sock.sendall(client_frame(8, payload[:2]))
                self.assertEqual(stream.read(1), b"")

        bad_origin = request.replace(b"https://local.test", b"https://wrong.test")
        self.assertIn(b"403 Forbidden", self.exchange(bad_origin))
        bad_version = request.replace(b"Sec-WebSocket-Version: 13", b"Sec-WebSocket-Version: 12")
        self.assertIn(b"426 Upgrade Required", self.exchange(bad_version))
        self.assertIn(b"400 Bad Request", self.exchange(request.replace(key, b"invalid")))

        for invalid, expected_code in (
            (client_frame(1, b"\xff"), 1007),
            (client_frame(2, b"x" * 129), 1009),
            (client_frame(9, b"x", fin=False), 1002),
        ):
            with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
                sock.settimeout(3)
                with sock.makefile("rb") as stream:
                    sock.sendall(request)
                    while stream.readline() != b"\r\n":
                        pass
                    self.assertEqual(server_frame(stream), (1, b"ready"))
                    sock.sendall(invalid)
                    opcode, payload = server_frame(stream)
                    self.assertEqual(opcode, 8)
                    self.assertEqual(payload[:2], expected_code.to_bytes(2, "big"))
                    sock.sendall(client_frame(8, payload[:2]))
                    self.assertEqual(stream.read(1), b"")

        state = self.exchange(b"GET /ws-state HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertGreaterEqual(int(state.split(b"\r\n\r\n", 1)[1]), 4)

    def test_producer_failure_closes_connection_and_source(self):
        count = lambda: int(self.exchange(
            b"GET /producer-closed HTTP/1.1\r\nHost: local\r\n\r\n"
        ).split(b"\r\n\r\n", 1)[1])
        before = count()
        result = self.exchange(b"GET /producer-error HTTP/1.1\r\nHost: local\r\n\r\n")
        headers, body = result.split(b"\r\n\r\n", 1)
        self.assertIn(b"Transfer-Encoding: chunked", headers)
        self.assertEqual(body, b"")
        self.assertEqual(count() - before, 1)
        self.assertIn(b"200 OK", self.exchange(
            b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
        ))

    def test_fragmented_post_and_parameter(self):
        response = self.exchange(
            b"POST /echo HTTP/1.1\r\nHo", b"st: local\r\nContent-Length: 5\r\n\r\nhe", b"llo"
        )
        self.assertTrue(response.endswith(b"hello"))
        self.assertTrue(
            self.exchange(b"GET /gpio/17 HTTP/1.0\r\n\r\n").endswith(b"17")
        )
        self.assertTrue(self.exchange(
            b"GET /gpio/fixed HTTP/1.1\r\nHost: local\r\n\r\n"
        ).endswith(b"fixed"))
        self.assertTrue(self.exchange(
            b"GET /query?value=a%2Fb+c HTTP/1.1\r\nHost: local\r\n\r\n"
        ).endswith(b"a/b c"))

    def test_limits_and_framing(self):
        self.assertIn(b"414 URI Too Long", self.exchange(
            b"GET /" + b"x" * 300 + b" HTTP/1.1\r\nHost: local\r\n\r\n"
        ))
        self.assertIn(b"431 Request Header Fields Too Large", self.exchange(
            b"GET /status HTTP/1.1\r\nHost: local\r\nX: " + b"x" * 1000 + b"\r\n\r\n"
        ))
        self.assertIn(b"413 Content Too Large", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 1025\r\n\r\n"
        ))
        self.assertIn(b"413 Content Too Large", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: "
            + b"9" * 100 + b"\r\n\r\n"
        ))
        self.assertIn(b"400 Bad Request", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nxx"
        ))
        self.assertIn(b"501 Not Implemented", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nTransfer-Encoding: gzip\r\n\r\n"
        ))
        self.assertIn(b"400 Bad Request", self.exchange(
            b"GET /status HTTP/1.1\r\n\r\n"
        ))
        self.assertIn(b"400 Bad Request", self.exchange(
            b"GET /query?value=%xx HTTP/1.1\r\nHost: local\r\n\r\n"
        ))

    def test_static_stream_and_traversal(self):
        served = self.exchange(b"GET /assets/large.txt HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertEqual(served.split(b"\r\n\r\n", 1)[1], b"abcdef0123456789" * 256)
        self.assertIn(b"403 Forbidden", self.exchange(
            b"GET /assets/%2e%2e/index.html HTTP/1.1\r\nHost: local\r\n\r\n"
        ))
        self.assertIn(b"400 Bad Request", self.exchange(
            b"GET /assets/%2fsecret HTTP/1.1\r\nHost: local\r\n\r\n"
        ))

    def test_static_byte_ranges_and_cache(self):
        base = b"GET /cached/large.txt HTTP/1.1\r\nHost: local\r\n"
        original = b"abcdef0123456789" * 256
        full = self.exchange(base + b"\r\n")
        headers, body = full.split(b"\r\n\r\n", 1)
        self.assertEqual(body, original)
        self.assertIn(b"Accept-Ranges: bytes", headers)
        self.assertIn(b"Cache-Control: public, max-age=60", headers)
        tag = next(line.split(b": ", 1)[1] for line in headers.split(b"\r\n")
                   if line.startswith(b"ETag: "))
        self.assertTrue(tag.startswith(b'W/"'))

        partial = self.exchange(base + b"Range: bytes=3-7\r\n\r\n")
        headers, body = partial.split(b"\r\n\r\n", 1)
        self.assertIn(b"206 Partial Content", headers)
        self.assertIn(b"Content-Range: bytes 3-7/4096", headers)
        self.assertIn(b"Content-Length: 5", headers)
        self.assertEqual(body, b"def01")

        for header, expected in ((b"Range: bytes=4090-\r\n", original[4090:]),
                                 (b"Range: bytes=-5\r\n", original[-5:])):
            response = self.exchange(base + header + b"\r\n")
            self.assertIn(b"206 Partial Content", response)
            self.assertEqual(response.split(b"\r\n\r\n", 1)[1], expected)

        unsatisfied = self.exchange(base + b"Range: bytes=5000-\r\n\r\n")
        headers, body = unsatisfied.split(b"\r\n\r\n", 1)
        self.assertIn(b"416 Range Not Satisfiable", headers)
        self.assertIn(b"Content-Range: bytes */4096", headers)
        self.assertEqual(body, b"")

        for value in (b"bytes=1-2,4-5", b"units=3-7", b"bytes=oops"):
            response = self.exchange(base + b"Range: " + value + b"\r\n\r\n")
            self.assertIn(b"200 OK", response)
            self.assertEqual(response.split(b"\r\n\r\n", 1)[1], original)

        head = self.exchange(b"HEAD /cached/large.txt HTTP/1.1\r\nHost: local\r\n"
                             b"Range: bytes=3-7\r\n\r\n")
        headers, body = head.split(b"\r\n\r\n", 1)
        self.assertIn(b"206 Partial Content", headers)
        self.assertIn(b"Content-Length: 5", headers)
        self.assertEqual(body, b"")

        not_modified = self.exchange(base + b"If-None-Match: " + tag + b"\r\n\r\n")
        headers, body = not_modified.split(b"\r\n\r\n", 1)
        self.assertIn(b"304 Not Modified", headers)
        self.assertEqual(body, b"")
        self.assertIn(b"200 OK", self.exchange(base + b"Range: bytes=3-7\r\n"
                                                 b"If-Range: other\r\n\r\n"))

        changing = b"GET /assets/changing.txt HTTP/1.1\r\nHost: local\r\n"
        first = self.exchange(changing + b"\r\n")
        old_tag = next(line.split(b": ", 1)[1] for line in first.split(b"\r\n\r\n", 1)[0].split(b"\r\n")
                       if line.startswith(b"ETag: "))
        (self.root / "changing.txt").write_bytes(b"after!")
        changed = self.exchange(changing + b"If-None-Match: " + old_tag + b"\r\n\r\n")
        headers, body = changed.split(b"\r\n\r\n", 1)
        self.assertIn(b"200 OK", headers)
        self.assertEqual(body, b"after!")
        new_tag = next(line.split(b": ", 1)[1] for line in headers.split(b"\r\n")
                       if line.startswith(b"ETag: "))
        self.assertNotEqual(new_tag, old_tag)

        huge = b"GET /assets/huge.bin HTTP/1.1\r\nHost: local\r\n"
        result = self.exchange(huge + b"\r\n")
        headers, body = result.split(b"\r\n\r\n", 1)
        self.assertNotIn(b"ETag:", headers)
        self.assertEqual(body, b"h" * 70000)
        result = self.exchange(huge + b"If-None-Match: *\r\n\r\n")
        self.assertIn(b"304 Not Modified", result)

    def test_one_request_per_connection(self):
        result = self.exchange(
            b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
            b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
        )
        self.assertEqual(result.count(b"HTTP/1.1 200"), 1)

    def test_keep_alive_sequential_requests(self):
        def read_response(stream, body=True):
            status = stream.readline()
            headers = {}
            while line := stream.readline():
                if line == b"\r\n":
                    break
                name, value = line.split(b":", 1)
                headers[name.lower()] = value.strip()
            payload = stream.read(int(headers[b"content-length"])) if body else b""
            return status, headers, payload

        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(2)
            with sock.makefile("rb") as stream:
                sock.sendall(b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n")
                status, headers, payload = read_response(stream)
                self.assertIn(b"200 OK", status)
                self.assertEqual(headers[b"connection"], b"keep-alive")
                self.assertEqual(payload, b'{"status":"ok"}')

                sock.sendall(b"HEAD /status HTTP/1.1\r\nHost: local\r\n\r\n")
                status, headers, payload = read_response(stream, body=False)
                self.assertIn(b"200 OK", status)
                self.assertEqual(headers[b"content-length"], b"15")
                self.assertEqual(payload, b"")

                sock.sendall(b"GET /assets/large.txt HTTP/1.1\r\nHost: local\r\n\r\n")
                status, headers, payload = read_response(stream)
                self.assertIn(b"200 OK", status)
                self.assertEqual(payload, b"abcdef0123456789" * 256)

                sock.sendall(b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 3\r\n\r\nhey")
                status, headers, payload = read_response(stream)
                self.assertIn(b"200 OK", status)
                self.assertEqual(headers[b"connection"], b"close")
                self.assertEqual(payload, b"hey")
                self.assertEqual(stream.read(1), b"")

    def test_keep_alive_idle_and_pipelining(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(2)
            sock.sendall(b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n")
            first = bytearray()
            while b'{"status":"ok"}' not in first:
                first.extend(sock.recv(4096))
            self.assertIn(b"Connection: keep-alive", first)
            time.sleep(0.65)
            self.assertEqual(sock.recv(1), b"")

        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.settimeout(2)
            sock.sendall(
                b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
                b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
            )
            response = bytearray()
            while part := sock.recv(4096):
                response.extend(part)
            self.assertEqual(response.count(b"HTTP/1.1 200"), 1)
            self.assertIn(b"Connection: close", response)

    def test_chunked_buffered_and_streamed_bodies(self):
        result = self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nTransfer-Encoding: chunked\r\n\r\n",
            b"5;note=x\r\nhe", b"llo\r", b"\n1\r\n!\r\n0\r\nX-Check: yes\r\n\r\n",
        )
        self.assertTrue(result.endswith(b"hello!"))
        body = bytes(range(256)) * 128
        frames = [b"POST /upload HTTP/1.1\r\nHost: local\r\nTransfer-Encoding: chunked\r\n\r\n"]
        for start in range(0, len(body), 512):
            part = body[start:start + 512]
            frames.append(f"{len(part):x}\r\n".encode() + part + b"\r\n")
        frames.append(b"0\r\n\r\n")
        response = self.exchange(*frames)
        self.assertIn(b"200 OK", response)
        size, chunks, checksum = map(int, response.split(b"\r\n\r\n", 1)[1].decode().split(":"))
        self.assertEqual(size, len(body))
        self.assertGreater(chunks, 1)
        self.assertEqual(checksum, sum(body) % 65521)

    def test_chunked_framing_errors(self):
        prefix = b"POST /echo HTTP/1.1\r\nHost: local\r\nTransfer-Encoding: chunked\r\n\r\n"
        self.assertIn(b"400 Bad Request", self.exchange(prefix + b"1\r\nx!\r\n0\r\n\r\n"))
        self.assertIn(b"400 Bad Request", self.exchange(prefix + b"z\r\n"))
        self.assertIn(b"413 Content Too Large", self.exchange(prefix + b"401\r\n"))
        self.assertIn(b"400 Bad Request", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 1\r\n"
            b"Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n"))
        self.assertIn(b"400 Bad Request", self.exchange(prefix + b"0\r\nContent-Length: 0\r\n\r\n"))

    def test_slow_clients_and_concurrency(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as slow:
            slow.settimeout(2)
            slow.sendall(b"GET /status HTTP/1.1\r\nHo")
            concurrent = self.exchange(b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n")
            self.assertIn(b"200 OK", concurrent)
            time.sleep(0.4)
            self.assertIn(b"408 Request Timeout", slow.recv(4096))
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as slow:
            slow.settimeout(2)
            slow.sendall(b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 4\r\n\r\na")
            time.sleep(0.4)
            self.assertIn(b"408 Request Timeout", slow.recv(4096))

    def test_disconnect_and_method_rejection(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.sendall(b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 10\r\n\r\nx")
        time.sleep(0.05)  # Let the service loop retire the disconnected slot.
        self.assertIn(b"200 OK", self.exchange(
            b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
        ))
        response = self.exchange(b"POST /status HTTP/1.1\r\nHost: local\r\nContent-Length: 0\r\n\r\n")
        self.assertIn(b"405 Method Not Allowed", response)
        self.assertIn(b"Allow: GET, HEAD", response)

    def test_restart_after_serving(self):
        self.assertIn(b"200 OK", self.exchange(
            b"GET /restart HTTP/1.1\r\nHost: local\r\n\r\n"
        ))
        time.sleep(0.05)
        self.assertIn(b"200 OK", self.exchange(
            b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
        ))

    def test_handler_exception_recovers(self):
        failure = self.exchange(b"GET /throw HTTP/1.1\r\nHost: local\r\n\r\n")
        self.assertIn(b"500 Internal Server Error", failure)
        self.assertIn(b"200 OK", self.exchange(
            b"GET /status HTTP/1.1\r\nHost: local\r\n\r\n"
        ))

    def test_streamed_request_body_and_limit(self):
        body = bytes(range(256)) * 128
        header = (b"POST /upload HTTP/1.1\r\nHost: local\r\n"
                  b"Content-Length: 32768\r\n\r\n")
        result = self.exchange(header + body[:13], body[13:4096], body[4096:])
        self.assertIn(b"200 OK", result)
        payload = result.split(b"\r\n\r\n", 1)[1].decode()
        size, chunks, checksum = map(int, payload.split(":"))
        self.assertEqual(size, len(body))
        self.assertGreater(chunks, 1)
        self.assertEqual(checksum, sum(body) % 65521)
        self.assertIn(b"200 OK", self.exchange(
            b"PUT /upload HTTP/1.1\r\nHost: local\r\n"
            b"Content-Length: 3\r\n\r\nabc"
        ))
        self.assertIn(b"411 Length Required", self.exchange(
            b"PUT /upload HTTP/1.1\r\nHost: local\r\n\r\n"
        ))
        self.assertTrue(self.exchange(
            b"POST /upload HTTP/1.1\r\nHost: local\r\n"
            b"Content-Length: 0\r\n\r\n"
        ).endswith(b"0:0:0"))
        self.assertIn(b"413 Content Too Large", self.exchange(
            b"POST /upload HTTP/1.1\r\nHost: local\r\n"
            b"Content-Length: 65537\r\n\r\n"
        ))
        with socket.create_connection(("127.0.0.1", self.port), timeout=2) as sock:
            sock.sendall(b"POST /upload HTTP/1.1\r\nHost: local\r\n"
                         b"Content-Length: 32768\r\n\r\npartial")
        time.sleep(0.05)
        self.assertTrue(self.exchange(
            b"GET /upload-aborts HTTP/1.1\r\nHost: local\r\n\r\n"
        ).endswith(b"1"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_httpserver_host.py SERVER_BINARY")
    unittest.main(argv=[sys.argv[0]], verbosity=2)
