"""Download pinned public model/test files; never read or upload user audio."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import io
import json
import tempfile
import time
import urllib.error
import urllib.request

REPO = "chegrowk/ko-phone-int8"
REVISION = "dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70"
MODEL_SIZE = 356129122
MODEL_SHA256 = "c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134"
SOURCE_REPO = "slplab/wav2vec2-xls-r-300m_phone-mfa_korean"
SOURCE_REVISION = "e26ff9dfb62169acf445d0060ef56863c018b20e"
ROOT = Path(__file__).resolve().parents[2] / ".local/pronunciation-spike"
FILES = ["config.json", "vocab.json", "preprocessor_config.json", "tokenizer_config.json",
         "special_tokens_map.json", "added_tokens.json", "README.md", "LICENSE", "onnx/model_quantized.onnx"]
FIXTURE_REPO = "k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16"
FIXTURE_REVISION = "ba6078bca4daf3f0dd37f79d0ab505af71df14a6"
FIXTURE_FILES = ["test_wavs/README.md", "test_wavs/trans.txt", "test_wavs/0.wav", "test_wavs/2.wav"]


def safe_path(root, name):
    parts = PurePosixPath(name)
    if not name or name == "." or parts.is_absolute() or ".." in parts.parts or "\\" in name or ":" in name:
        raise ValueError(f"Unsafe relative path: {name}")
    target = (root / name).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError(f"Path escapes asset directory: {name}")
    return target


def verify_file(target, metadata):
    if target.stat().st_size != metadata["size"]:
        raise ValueError(f"Size mismatch: {target.name}")
    sha256 = hashlib.sha256()
    blob = hashlib.sha1(f"blob {metadata['size']}\0".encode())
    with target.open("rb") as file:
        while chunk := file.read(1024 * 1024):
            sha256.update(chunk)
            blob.update(chunk)
    digest = sha256.hexdigest()
    expected = metadata.get("lfs", {}).get("sha256")
    if (expected and digest != expected) or (not expected and blob.hexdigest() != metadata.get("blobId")):
        raise ValueError(f"Digest mismatch: {target.name}")
    return digest


def download_file(root, name, url, metadata, opener=urllib.request.urlopen):
    target = safe_path(root, name)
    started = time.perf_counter()
    cached = False
    if target.is_file():
        try:
            digest = verify_file(target, metadata)
            cached = True
        except ValueError:
            pass
    if not cached:
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with opener(url, timeout=90) as response:
                with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".", suffix=".part", delete=False) as out:
                    temporary = Path(out.name)
                    received = 0
                    while chunk := response.read(1024 * 1024):
                        received += len(chunk)
                        if received > metadata["size"]:
                            raise ValueError(f"Download exceeds expected size: {name}")
                        out.write(chunk)
            digest = verify_file(temporary, metadata)
            temporary.replace(target)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return {"file": name, "bytes": metadata["size"], "sha256": digest, "url": url,
            "gitBlobId": metadata.get("blobId"), "lfsSha256": metadata.get("lfs", {}).get("sha256"),
            "cached": cached, "seconds": round(time.perf_counter() - started, 3)}


def read_metadata(repo, revision):
    url = f"https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true"
    with urllib.request.urlopen(url, timeout=60) as response:
        metadata = json.load(response)
    if metadata["sha"] != revision:
        raise ValueError("Metadata revision does not match pinned revision")
    return metadata, url


def main():
    started = time.perf_counter()
    metadata, metadata_url = read_metadata(REPO, REVISION)
    entries = {entry["rfilename"]: entry for entry in metadata["siblings"]}
    model = entries["onnx/model_quantized.onnx"]
    if model["size"] != MODEL_SIZE or model["lfs"]["sha256"] != MODEL_SHA256:
        raise ValueError("Remote model identity differs from pinned size/SHA-256")
    source, source_url = read_metadata(SOURCE_REPO, SOURCE_REVISION)
    source_entries = {entry["rfilename"]: entry for entry in source["siblings"]}
    report = []
    for name in FILES:
        result = download_file(ROOT, name, f"https://huggingface.co/{REPO}/resolve/{REVISION}/{name}", entries[name])
        report.append(result)
        print(json.dumps(result), flush=True)
    report.append(download_file(ROOT, "source-model-card.md",
        f"https://huggingface.co/{SOURCE_REPO}/resolve/{SOURCE_REVISION}/README.md", source_entries["README.md"]))
    ROOT.joinpath("model-metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    ROOT.joinpath("source-metadata.json").write_text(json.dumps(source, indent=2), encoding="utf-8")
    manifest = {"repository": REPO, "revision": REVISION, "metadataUrl": metadata_url,
        "license": metadata.get("cardData", {}).get("license"),
        "source": {"repository": SOURCE_REPO, "revision": SOURCE_REVISION, "metadataUrl": source_url,
                   "license": source.get("cardData", {}).get("license")},
        "files": report, "totalSeconds": round(time.perf_counter() - started, 3),
        "verification": "LFS SHA-256 or Git blob SHA-1 verified against pinned-revision metadata; SHA-256 recorded for every asset",
        "audioUploaded": False}
    temporary = ROOT / "manifest.json.part"
    temporary.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    temporary.replace(ROOT / "manifest.json")
    print(f"Verified manifest: {ROOT / 'manifest.json'}", flush=True)
    fixture_metadata, fixture_url = read_metadata(FIXTURE_REPO, FIXTURE_REVISION)
    fixture_entries = {entry["rfilename"]: entry for entry in fixture_metadata["siblings"]}
    fixture_report = []
    for name in FIXTURE_FILES:
        fixture_report.append(download_file(ROOT, "fixtures/" + name,
            f"https://huggingface.co/{FIXTURE_REPO}/resolve/{FIXTURE_REVISION}/{name}", fixture_entries[name]))
    fixture_manifest = {"repository": FIXTURE_REPO, "revision": FIXTURE_REVISION, "metadataUrl": fixture_url,
        "kind": "public Korean ASR test WAV; not user audio or human-labeled pronunciation-error examples",
        "files": fixture_report}
    ROOT.joinpath("fixture-manifest.json").write_text(json.dumps(fixture_manifest, indent=2), encoding="utf-8")
    print("Verified public fixtures: 0.wav, 2.wav and their source/read-text documents", flush=True)


def self_check():
    payload = b"pinned public model test"
    entry = {"size": len(payload), "lfs": {"sha256": hashlib.sha256(payload).hexdigest()}}
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for bad in ["../escape", "/absolute", "C:/escape", "a\\..\\escape", "a/../../escape", ".", ""]:
            try:
                safe_path(root, bad)
                raise AssertionError(f"unsafe path accepted: {bad}")
            except ValueError:
                pass
        for label, body in [("short", payload[:-1]), ("oversize", payload + b"x"), ("hash", b"x" * len(payload))]:
            try:
                download_file(root, label, "https://example.invalid/test", entry,
                              lambda *args, **kwargs: io.BytesIO(body))
                raise AssertionError(f"invalid download accepted: {label}")
            except ValueError:
                pass
            assert not (root / label).exists()
            assert not list(root.rglob("*.part"))
        def http_error(*args, **kwargs):
            raise urllib.error.HTTPError("https://example.invalid", 404, "missing", {}, None)
        try:
            download_file(root, "missing", "https://example.invalid", entry, http_error)
            raise AssertionError("HTTP failure accepted")
        except urllib.error.HTTPError:
            pass
        assert not (root / "missing").exists()
        assert not list(root.rglob("*.part"))
        first = download_file(root, "valid", "https://example.invalid", entry,
                              lambda *args, **kwargs: io.BytesIO(payload))
        cached = download_file(root, "valid", "https://example.invalid", entry, http_error)
        assert not first["cached"] and cached["cached"]
        (root / "valid").write_bytes(b"x" * len(payload))
        repaired = download_file(root, "valid", "https://example.invalid", entry,
                                 lambda *args, **kwargs: io.BytesIO(payload))
        assert not repaired["cached"] and (root / "valid").read_bytes() == payload
        blob_entry = {"size": len(payload), "blobId": hashlib.sha1(
            f"blob {len(payload)}\0".encode() + payload).hexdigest()}
        download_file(root, "git-blob", "https://example.invalid", blob_entry,
                      lambda *args, **kwargs: io.BytesIO(payload))
    print("self-check passed: traversal, short/oversize/hash/HTTP failures, cache verification, Git blob integrity")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-check", action="store_true")
    options = parser.parse_args()
    if options.self_check:
        self_check()
    else:
        main()
