"""Serve only the pronunciation spike's fixed assets on IPv4 loopback."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]
PAGE = "/tools/pronunciation-spike/index.html"
ROUTES = {
    **{f"/tools/pronunciation-spike/{name}": f"tools/pronunciation-spike/{name}"
       for name in ("index.html", "styles.css", "app.mjs", "worker.mjs", "client.mjs", "audio.mjs",
                    "phones.mjs", "phone-engine.mjs", "recording.mjs", "capture-worklet.mjs")},
    **{f"/apps/client/web/prosody/vendor/onnx/{name}":
       f"apps/client/web/prosody/vendor/onnx/{name}"
       for name in ("ort.wasm.min.mjs", "ort-wasm-simd-threaded.mjs", "ort-wasm-simd-threaded.wasm")},
    **{f"/apps/client/web/pronunciation/{name}": f"apps/client/web/pronunciation/{name}"
       for name in ("audio.mjs", "phones.mjs", "ipa-phones.mjs", "phone-engine.mjs", "client.mjs",
                    "recording.mjs", "capture-worklet.mjs", "sha256.mjs",
                    "vendor/hash-wasm/sha256.umd.min.js", "vendor/onnx/ort.wasm.min.mjs")},
    **{f"/.local/pronunciation-ipa/{name}": f".local/pronunciation-ipa/{name}"
       for name in ("config.json", "vocab.json", "added_tokens.json",
                    "preprocessor_config.json", "ko-ipa.onnx", "model.safetensors")},
    "/fonts/PretendardVariable.ttf": "apps/client/assets/fonts/PretendardVariable.ttf",
}
MIMES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
         ".mjs": "application/javascript", ".js": "application/javascript", ".wasm": "application/wasm",
         ".json": "application/json", ".ttf": "font/ttf", ".onnx": "application/octet-stream", ".safetensors": "application/octet-stream"}
CSP = ("default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; worker-src 'self'; "
       "connect-src 'self'; media-src 'self' blob:; object-src 'none'; "
       "frame-ancestors 'none'; base-uri 'none'; form-action 'none'")


class Handler(BaseHTTPRequestHandler):
    def parse_request(self):
        if not super().parse_request():
            return False
        hosts = self.headers.get_all("Host", [])
        port = self.server.server_port
        if len(hosts) != 1 or hosts[0] not in (f"127.0.0.1:{port}", f"localhost:{port}"):
            self.send_error(403, "Loopback Host required")
            return False
        origins = self.headers.get_all("Origin", [])
        if origins and origins != [f"http://{hosts[0]}"]:
            self.send_error(403, "Same-origin request required")
            return False
        if self.command not in ("GET", "HEAD"):
            self.send_response(405)
            self.send_header("Allow", "GET, HEAD")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False
        return True

    def end_headers(self):
        self.send_header("Content-Security-Policy", CSP)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        # Inspect the original target because BaseHTTPRequestHandler normalizes leading //.
        raw = self.requestline.split()[1]
        try:
            parsed = urlsplit(raw)
            decoded = unquote(parsed.path, errors="strict")
        except (ValueError, UnicodeError):
            self.send_error(400, "Invalid path")
            return
        if (not raw.startswith("/") or raw.startswith("//") or parsed.scheme or parsed.netloc
                or parsed.fragment or decoded != parsed.path or "\\" in decoded
                or any(part in (".", "..") for part in decoded.split("/"))):
            self.send_error(400, "Invalid path")
            return
        if decoded == "/":
            self.send_response(302)
            self.send_header("Location", PAGE)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        relative = ROUTES.get(decoded)
        if relative is None:
            self.send_error(404, "Not found")
            return
        target = self.server.root / relative
        try:
            if target.resolve(strict=True) != target or not target.is_file():
                raise FileNotFoundError
            source = target.open("rb")
        except (OSError, RuntimeError):
            self.send_error(404, "Not found")
            return
        with source:
            self.send_response(200)
            self.send_header("Content-Type", MIMES[target.suffix])
            self.send_header("Content-Length", str(os.fstat(source.fileno()).st_size))
            self.end_headers()
            if self.command != "HEAD":
                try:
                    shutil.copyfileobj(source, self.wfile)
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                    pass

    do_HEAD = do_GET

    def log_message(self, format, *args):
        pass


def create_server(port=8093, root=ROOT):
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.root = Path(root).resolve()
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8093)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    with create_server(args.port) as server:
        print(f"http://127.0.0.1:{server.server_port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
