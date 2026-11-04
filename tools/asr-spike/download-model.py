"""Download only pinned public model assets; never send audio or scripts."""
from pathlib import Path
import hashlib, json, time, urllib.request

REVISION = 'ba6078bca4daf3f0dd37f79d0ab505af71df14a6'
REPO = 'k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16'
ROOT = Path(__file__).resolve().parents[2] / '.local/asr-spike'
FILES = ['encoder-epoch-99-avg-1.int8.onnx', 'decoder-epoch-99-avg-1.onnx',
         'joiner-epoch-99-avg-1.int8.onnx', 'tokens.txt', 'README.md',
         'test_wavs/README.md', 'test_wavs/trans.txt'] + [f'test_wavs/{i}.wav' for i in range(4)]
ROOT.mkdir(parents=True, exist_ok=True)
trusted = {x['file']: x['sha256'] for x in json.loads(
    (Path(__file__).parent / 'evidence/download-report.json').read_text(encoding='utf-8'))}
metadata = json.load(urllib.request.urlopen(f'https://huggingface.co/api/models/{REPO}/tree/{REVISION}?recursive=true'))
metadata = {entry['path']: entry for entry in metadata}
report = []
for name in FILES:
    entry = metadata[name]
    target = ROOT / name
    target.parent.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter()
    cached = target.is_file() and target.stat().st_size == entry['size']
    if not cached:
        with urllib.request.urlopen(f'https://huggingface.co/{REPO}/resolve/{REVISION}/{name}', timeout=60) as response:
            with target.open('wb') as out:
                while chunk := response.read(1024 * 1024):
                    out.write(chunk)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    assert digest == trusted[name], f'Pinned digest mismatch: {name}'
    assert target.stat().st_size == entry['size'], name
    if entry.get('lfs'):
        assert digest == entry['lfs']['oid'], name
    report.append({'file': name, 'bytes': entry['size'], 'sha256': digest,
                   'seconds': round(time.perf_counter()-start, 3), 'cached': cached})
    print(json.dumps(report[-1]), flush=True)
(ROOT / 'download-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
