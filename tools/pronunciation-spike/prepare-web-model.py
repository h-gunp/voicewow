"""Prepare verified ORT model parts in the local cache, outside Flutter assets."""
import argparse
import hashlib
from pathlib import Path
import runpy
import tempfile
import urllib.request


DOWNLOAD = runpy.run_path(str(Path(__file__).with_name("download-model.py")))
ROOT = Path(__file__).resolve().parents[2]
BUNDLED = ".local/pronunciation-spike/web-model/ko-phone-int8.ort"
PART_BYTES = 16 * 1024 * 1024
PUBLIC_URL = "https://raw.githubusercontent.com/h-gunp/voicewow/72bb26aa05c94763dfab5f150a7ae747a1937e10/ko-phone-int8.ort"
ORT_METADATA = {"size": 356216776, "lfs": {"sha256":
    "a280f2679f08c809ae3c5ad55abe15dc78803e06143cc9b485c143612652765e"}}


def valid(path, metadata):
    try:
        DOWNLOAD["verify_file"](path, metadata)
        return True
    except (FileNotFoundError, ValueError):
        return False


def verify_parts(root, relative, metadata, part_bytes=PART_BYTES):
    target = DOWNLOAD["safe_path"](root, relative)
    count = (metadata["size"] + part_bytes - 1) // part_bytes
    parts = [target.with_name(f"{target.name}.part{index:02d}") for index in range(count)]
    if set(target.parent.glob(target.name + ".part[0-9][0-9]")) != set(parts):
        raise ValueError("Bundled model part count does not match")
    digest = hashlib.sha256()
    for index, part in enumerate(parts):
        if part.stat().st_size != min(part_bytes, metadata["size"] - index * part_bytes):
            raise ValueError(f"Model part size mismatch: {part.name}")
        with part.open("rb") as file:
            while chunk := file.read(1024 * 1024):
                digest.update(chunk)
    if digest.hexdigest() != metadata["lfs"]["sha256"]:
        raise ValueError("Bundled model SHA-256 mismatch")


def stage_verified(source, root, relative, metadata, part_bytes=PART_BYTES):
    target = DOWNLOAD["safe_path"](root, relative)
    DOWNLOAD["verify_file"](source, metadata)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".model-", dir=target.parent) as directory:
        staging = Path(directory)
        with source.open("rb") as file:
            for index in range((metadata["size"] + part_bytes - 1) // part_bytes):
                remaining = min(part_bytes, metadata["size"] - index * part_bytes)
                with (staging / f"{target.name}.part{index:02d}").open("wb") as output:
                    while remaining:
                        chunk = file.read(min(1024 * 1024, remaining))
                        if not chunk:
                            raise ValueError("Model source ended during split")
                        output.write(chunk)
                        remaining -= len(chunk)
        verify_parts(staging, target.name, metadata, part_bytes)
        for part in staging.iterdir():
            part.replace(target.parent / part.name)
    verify_parts(root, relative, metadata, part_bytes)


def download_canonical(target, metadata, part_bytes=PART_BYTES, opener=urllib.request.urlopen):
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, suffix=".part", delete=False) as output:
            temporary = Path(output.name)
            for index in range((metadata["size"] + part_bytes - 1) // part_bytes):
                expected = min(part_bytes, metadata["size"] - index * part_bytes)
                received = 0
                with opener(f"{PUBLIC_URL}.part{index:02d}", timeout=90) as response:
                    while chunk := response.read(1024 * 1024):
                        received += len(chunk)
                        if received > expected:
                            raise ValueError(f"Downloaded model part {index} exceeds expected size")
                        output.write(chunk)
                if received != expected:
                    raise ValueError(f"Downloaded model part {index} is incomplete")
        DOWNLOAD["verify_file"](temporary, metadata)
        temporary.replace(target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def prepare(check_only=False):
    target = DOWNLOAD["safe_path"](ROOT, BUNDLED)
    try:
        verify_parts(ROOT, BUNDLED, ORT_METADATA)
    except (FileNotFoundError, ValueError):
        if check_only:
            raise
        converted = DOWNLOAD["safe_path"](ROOT, ".local/pronunciation-spike/onnx/model_quantized.extended.ort")
        if not valid(converted, ORT_METADATA):
            download_canonical(converted, ORT_METADATA)
        stage_verified(converted, ROOT, BUNDLED, ORT_METADATA)
    print(f"Verified local model parts: {target}.part00... ({ORT_METADATA['size']} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify bundled parts without downloading or modifying files")
    args = parser.parse_args()
    try:
        prepare(check_only=args.check)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, f"Model preparation failed: {error}\n")
