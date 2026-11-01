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
            for fragment in fragments:
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
        self.assertIn(b"400 Bad Request", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nxx"
        ))
        self.assertIn(b"501 Not Implemented", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: local\r\nTransfer-Encoding: chunked\r\n\r\n"
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


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_httpserver_host.py SERVER_BINARY")
    unittest.main(argv=[sys.argv[0]], verbosity=2)
