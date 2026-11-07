import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest


class PreparationTests(unittest.TestCase):
    def builder(self):
        path = Path(__file__).with_name("prepare-web-model.py")
        self.assertTrue(path.is_file(), "web model preparation command is missing")
        spec = importlib.util.spec_from_file_location("prepare_web_model", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_verified_split_rejects_bad_source_without_replacing_existing_parts(self):
        builder = self.builder()
        payload = b"verified model"
        metadata = {"size": len(payload), "lfs": {"sha256": hashlib.sha256(payload).hexdigest()}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "source.ort", root / "models/bundled.ort.part00"
            target.parent.mkdir()
            target.write_bytes(b"existing model")
            for data in (payload[:-1], payload + b"x", b"x" * len(payload)):
                source.write_bytes(data)
                with self.assertRaises(ValueError):
                    builder.stage_verified(source, root, "models/bundled.ort", metadata, part_bytes=4)
                self.assertEqual(target.read_bytes(), b"existing model")
                self.assertEqual(list(root.rglob("*.part")), [])
            source.write_bytes(payload)
            builder.stage_verified(source, root, "models/bundled.ort", metadata, part_bytes=4)
            parts = sorted(target.parent.glob("*.part??"))
            self.assertEqual([part.stat().st_size for part in parts], [4, 4, 4, 2])
            self.assertEqual(b"".join(part.read_bytes() for part in parts), payload)
            builder.verify_parts(root, "models/bundled.ort", metadata, part_bytes=4)
            for data in (b"xxxx", b"verix"):
                parts[0].write_bytes(data)
                with self.assertRaises(ValueError):
                    builder.verify_parts(root, "models/bundled.ort", metadata, part_bytes=4)
            parts[0].write_bytes(b"veri")
            extra = target.parent / "bundled.ort.part04"
            extra.write_bytes(b"x")
            with self.assertRaises(ValueError):
                builder.verify_parts(root, "models/bundled.ort", metadata, part_bytes=4)
            extra.unlink()
            parts[-1].unlink()
            with self.assertRaises(ValueError):
                builder.verify_parts(root, "models/bundled.ort", metadata, part_bytes=4)

    def test_copy_rejects_paths_outside_asset_root(self):
        builder = self.builder()
        payload = b"verified model"
        metadata = {"size": len(payload), "lfs": {"sha256": hashlib.sha256(payload).hexdigest()}}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.ort"
            source.write_bytes(payload)
            for path in ("../escape.ort", "/absolute.ort", "C:/escape.ort", "a\\..\\escape.ort"):
                with self.assertRaises(ValueError):
                    builder.stage_verified(source, root, path, metadata)

    def test_check_only_validates_bundle_without_downloading_or_repairing(self):
        builder = self.builder()
        payload = b"verified model"
        builder.ORT_METADATA = {"size": len(payload), "lfs": {"sha256": hashlib.sha256(payload).hexdigest()}}
        def download_forbidden(*args, **kwargs):
            self.fail("check-only attempted a download")
        builder.download_canonical = download_forbidden
        with tempfile.TemporaryDirectory() as directory:
            builder.ROOT = Path(directory)
            target = builder.ROOT / (builder.BUNDLED + ".part00")
            target.parent.mkdir(parents=True)
            target.write_bytes(payload)
            builder.prepare(check_only=True)
            target.write_bytes(b"x" * len(payload))
            with self.assertRaises(ValueError):
                builder.prepare(check_only=True)
            self.assertEqual(target.read_bytes(), b"x" * len(payload))

    def test_download_rejects_missing_short_oversize_or_corrupt_parts_atomically(self):
        builder, payload = self.builder(), b"verified model"
        metadata = {"size": len(payload), "lfs": {"sha256": hashlib.sha256(payload).hexdigest()}}
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "model.ort"
            target.write_bytes(b"existing")
            for bad in (b"", b"12345", b"xxxx"):
                with self.assertRaises(ValueError):
                    builder.download_canonical(target, metadata, part_bytes=4,
                        opener=lambda *args, **kwargs: io.BytesIO(bad))
                self.assertEqual(target.read_bytes(), b"existing")
            def missing(*args, **kwargs):
                raise OSError("missing part")
            with self.assertRaises(OSError):
                builder.download_canonical(target, metadata, part_bytes=4, opener=missing)
            corrupted = iter((b"xxxx", b"fied", b" mod", b"el"))
            with self.assertRaises(ValueError):
                builder.download_canonical(target, metadata, part_bytes=4,
                    opener=lambda *args, **kwargs: io.BytesIO(next(corrupted)))
            self.assertEqual(target.read_bytes(), b"existing")
            chunks = iter((b"veri", b"fied", b" mod", b"el"))
            builder.download_canonical(target, metadata, part_bytes=4,
                opener=lambda *args, **kwargs: io.BytesIO(next(chunks)))
            self.assertEqual(target.read_bytes(), payload)
            self.assertEqual(list(target.parent.glob("*.part")), [])


if __name__ == "__main__":
    unittest.main()
