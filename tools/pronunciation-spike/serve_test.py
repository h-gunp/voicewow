"""Exercise the actual loopback HTTP boundary without loading model weights."""
import http.client
import importlib.util
from pathlib import Path
import tempfile
import threading
import unittest


MODULE = Path(__file__).with_name("serve.py")
PAGE = "/tools/pronunciation-spike/index.html"
ROUTES = {
    **{f"/apps/client/web/audio/{name}": f"apps/client/web/audio/{name}"
       for name in ("processed-capture.mjs", "processed-capture-worklet.mjs", "noise-reduction.mjs",
                    "noise-reducer.mjs", "voice-activity.mjs", "level-meter.mjs",
                    "vendor/rnnoise/rnnoise.mjs", "vendor/rnnoise/rnnoise.wasm", "vendor/libfvad/libfvad.wasm")},
    **{f"/tools/pronunciation-spike/{name}": f"tools/pronunciation-spike/{name}"
       for name in ("index.html", "styles.css", "app.mjs", "worker.mjs", "client.mjs", "audio.mjs",
                    "phones.mjs", "phone-engine.mjs", "recording.mjs", "capture-worklet.mjs")},
    **{f"/apps/client/web/prosody/vendor/onnx/{name}":
       f"apps/client/web/prosody/vendor/onnx/{name}"
       for name in ("ort.wasm.min.mjs", "ort-wasm-simd-threaded.mjs", "ort-wasm-simd-threaded.wasm")},
    **{f"/apps/client/web/pronunciation/{name}": f"apps/client/web/pronunciation/{name}"
       for name in ("audio.mjs", "phones.mjs", "ipa-phones.mjs", "phone-engine.mjs", "client.mjs",
                    "recording.mjs", "capture-worklet.mjs")},
    **{f"/.local/pronunciation-ipa/{name}": f".local/pronunciation-ipa/{name}"
       for name in ("config.json", "vocab.json", "added_tokens.json",
                    "preprocessor_config.json", "ko-ipa.onnx", "model.safetensors")},
    "/fonts/PretendardVariable.ttf": "apps/client/assets/fonts/PretendardVariable.ttf",
}


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.is_file(), "The allowlisted loopback server is not implemented")
        spec = importlib.util.spec_from_file_location("pronunciation_server", MODULE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for route, relative in ROUTES.items():
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(route.encode())
        self.server = module.create_server(port=0, root=self.root)
        self.port = self.server.server_address[1]
        self.host = f"127.0.0.1:{self.port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, path=PAGE, method="GET", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            connection.putrequest(method, path, skip_host=True)
            for key, value in (headers if headers is not None else [("Host", self.host)]):
                connection.putheader(key, value)
            connection.endheaders()
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def test_binds_only_loopback_and_redirects_root(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        status, headers, body = self.request("/")
        self.assertEqual(status, 302)
        self.assertEqual(headers["Location"], PAGE)
        self.assertEqual(body, b"")

    def test_every_allowed_file_and_font_alias_is_served(self):
        for route in ROUTES:
            with self.subTest(route=route):
                status, headers, body = self.request(route)
                self.assertEqual(status, 200)
                self.assertEqual(body, route.encode())
                self.assertEqual(int(headers["Content-Length"]), len(body))

    def test_mime_and_security_headers(self):
        for route, mime in (("/tools/pronunciation-spike/app.mjs", "application/javascript"),
                            ("/apps/client/web/prosody/vendor/onnx/ort-wasm-simd-threaded.wasm", "application/wasm")):
            with self.subTest(route=route):
                status, headers, _ = self.request(route)
                self.assertEqual(status, 200)
                self.assertEqual(headers["Content-Type"], mime)
                self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
                self.assertEqual(headers["Cross-Origin-Opener-Policy"], "same-origin")
                self.assertEqual(headers["Cross-Origin-Embedder-Policy"], "require-corp")
                self.assertNotIn("Access-Control-Allow-Origin", headers)
                csp = headers["Content-Security-Policy"]
                for directive in ("default-src 'self'", "script-src 'self' 'wasm-unsafe-eval'",
                                  "worker-src 'self'", "connect-src 'self'", "media-src 'self' blob:",
                                  "object-src 'none'", "frame-ancestors 'none'",
                                  "base-uri 'none'", "form-action 'none'"):
                    self.assertIn(directive, csp)

    def test_head_matches_get_without_body(self):
        status, headers, body = self.request(method="HEAD")
        self.assertEqual(status, 200)
        self.assertEqual(int(headers["Content-Length"]), len(PAGE))
        self.assertEqual(body, b"")

    def test_host_requires_exact_loopback_name_and_port(self):
        for host in (self.host, f"localhost:{self.port}"):
            self.assertEqual(self.request(headers=[("Host", host)])[0], 200)
        bad_hosts = ("evil.example", f"evil.example:{self.port}", "127.0.0.1", "localhost",
                     f"127.0.0.1:{self.port + 1}", f"localhost.evil:{self.port}",
                     f"127.0.0.1:{self.port}@evil.example", f"[::1]:{self.port}")
        for host in bad_hosts:
            with self.subTest(host=host):
                self.assertEqual(self.request(headers=[("Host", host)])[0], 403)
        self.assertEqual(self.request(headers=[])[0], 403)
        self.assertEqual(self.request(headers=[("Host", self.host), ("Host", self.host)])[0], 403)

    def test_origin_if_present_must_match_host(self):
        self.assertEqual(self.request(headers=[("Host", self.host), ("Origin", f"http://{self.host}")])[0], 200)
        for origin in ("null", "https://evil.example", f"https://{self.host}",
                       f"http://localhost:{self.port}", f"http://{self.host}/"):
            with self.subTest(origin=origin):
                self.assertEqual(self.request(headers=[("Host", self.host), ("Origin", origin)])[0], 403)
        self.assertEqual(self.request(headers=[("Host", self.host),
                         ("Origin", f"http://{self.host}"), ("Origin", f"http://{self.host}")])[0], 403)

    def test_sensitive_files_and_directory_indexes_are_unavailable(self):
        for relative in (".env", "tools/pronunciation-spike/download-model.py",
                         "tools/pronunciation-spike/serve_test.py", ".local/pronunciation-ipa/fixture.wav",
                         ".local/pronunciation-ipa/manifest.json", "README.md"):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("secret", encoding="utf-8")
            status, _, body = self.request("/" + relative)
            self.assertEqual(status, 404, relative)
            self.assertNotIn(b"secret", body)
        for path in ("/tools/pronunciation-spike/", "/.local/", "/fonts/",
                     "/apps/client/assets/fonts/PretendardVariable.ttf"):
            self.assertEqual(self.request(path)[0], 404, path)

    def test_traversal_encoded_aliases_and_absolute_urls_are_rejected(self):
        for path in ("/tools/pronunciation-spike/../pronunciation-spike/index.html",
                     "/tools/pronunciation-spike/%2e%2e/pronunciation-spike/index.html",
                     "/tools/pronunciation-spike/%252e%252e/index.html",
                     "/tools/pronunciation-spike/%69ndex.html", PAGE + "%00",
                     "/tools\\pronunciation-spike\\index.html", "/tools/pronunciation-spike/./index.html",
                     "//tools/pronunciation-spike/index.html", "http://evil.example" + PAGE):
            with self.subTest(path=path):
                self.assertIn(self.request(path)[0], (400, 404))

    def test_other_methods_are_rejected(self):
        for method in ("POST", "PUT", "DELETE", "PATCH", "OPTIONS", "TRACE", "CONNECT"):
            with self.subTest(method=method):
                status, headers, _ = self.request(method=method)
                self.assertEqual(status, 405)
                self.assertEqual(headers["Allow"], "GET, HEAD")

    def test_missing_allowed_file_does_not_crash_server(self):
        (self.root / ROUTES[PAGE]).unlink()
        self.assertEqual(self.request()[0], 404)
        self.assertEqual(self.request("/fonts/PretendardVariable.ttf")[0], 200)


if __name__ == "__main__":
    unittest.main()
