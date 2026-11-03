#!/usr/bin/env python3
"""Run the shared HTTP wire contract against a configured ESP32 or Pico W."""

import argparse
import hashlib
import socket
import time
import unittest


parser = argparse.ArgumentParser()
parser.add_argument("host", help="board IP address")
parser.add_argument("--port", type=int, default=8080)
parser.add_argument("--static-path", help="optional /files/... or /sd/... fixture URL")
parser.add_argument("--static-sha256", help="SHA-256 of the optional static fixture")
args = parser.parse_args()


class DeviceHTTPTests(unittest.TestCase):
    def exchange(self, *fragments):
        with socket.create_connection((args.host, args.port), timeout=3) as sock:
            sock.settimeout(5)
            for fragment in fragments:
                sock.sendall(fragment)
                time.sleep(0.01)
            data = bytearray()
            while True:
                part = sock.recv(2048)
                if not part:
                    return bytes(data)
                data.extend(part)

    def test_status_head_and_close(self):
        get = self.exchange(b"GET /status HTTP/1.1\r\nHost: device\r\n\r\n")
        self.assertIn(b"200 OK", get)
        self.assertIn(b'"status":"ok"', get)
        self.assertIn(b"Connection: close", get)
        head = self.exchange(b"HEAD /status HTTP/1.1\r\nHost: device\r\n\r\n")
        self.assertIn(b"200 OK", head)
        self.assertEqual(head.split(b"\r\n\r\n", 1)[1], b"")

    def test_fragmented_body_and_malformed_framing(self):
        post = self.exchange(
            b"POST /echo HTTP/1.1\r\nHo",
            b"st: device\r\nContent-Length: 5\r\n\r\nhe",
            b"llo",
        )
        self.assertTrue(post.endswith(b"hello"))
        self.assertIn(b"400 Bad Request", self.exchange(
            b"GET /status HTTP/1.1\r\n\r\n"
        ))
        self.assertIn(b"413 Content Too Large", self.exchange(
            b"POST /echo HTTP/1.1\r\nHost: device\r\nContent-Length: 1025\r\n\r\n"
        ))

    def test_partial_disconnect_then_recovery(self):
        with socket.create_connection((args.host, args.port), timeout=3) as sock:
            sock.sendall(b"POST /echo HTTP/1.1\r\nHost: device\r\nContent-Length: 5\r\n\r\nx")
        time.sleep(0.1)
        self.assertIn(b"200 OK", self.exchange(
            b"GET /status HTTP/1.1\r\nHost: device\r\n\r\n"
        ))

    @unittest.skipUnless(args.static_path and args.static_sha256, "no static fixture supplied")
    def test_static_stream(self):
        result = self.exchange(
            f"GET {args.static_path} HTTP/1.1\r\nHost: device\r\n\r\n".encode("ascii")
        )
        self.assertIn(b"200 OK", result)
        body = result.split(b"\r\n\r\n", 1)[1]
        self.assertEqual(hashlib.sha256(body).hexdigest(), args.static_sha256.lower())


if __name__ == "__main__":
    unittest.main(argv=["test_httpserver_device.py"], verbosity=2)
