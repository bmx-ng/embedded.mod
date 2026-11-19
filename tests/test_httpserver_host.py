#!/usr/bin/env python3
"""Wire-level regressions for the shared embedded HTTP server on a host."""

import pathlib
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
        (root / "index.html").write_text("<h1>root</h1>", encoding="utf-8")
        (root / "large.txt").write_bytes(b"abcdef0123456789" * 256)
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
