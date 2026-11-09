"""Prepare pinned upstream IPA files for the loopback spike; uploads nothing."""
from pathlib import Path
import json
import runpy

ROOT = Path(__file__).resolve().parents[2]
DOWNLOAD = runpy.run_path(str(Path(__file__).with_name('download-model.py')))


def main():
    source = ROOT / 'apps/client/web/pronunciation/models'
    manifest = json.loads((source / 'source.json').read_text(encoding='utf-8'))
    target = ROOT / '.local/pronunciation-ipa'
    rows = []
    for asset in manifest['sources'] + [{**manifest['graph'], 'file': 'ko-ipa.onnx',
                                        'url': (source / 'ko-ipa.onnx').as_uri()}]:
        rows.append(DOWNLOAD['download_file'](target, asset['file'], asset['url'],
            {'size': asset['bytes'], 'lfs': {'sha256': asset['sha256']}}))
    (target / 'model-manifest.json').write_text(json.dumps({
        'repository': manifest['repository'], 'revision': manifest['revision'], 'files': rows,
    }, indent=2), encoding='utf-8')
    metadata, _ = DOWNLOAD['read_metadata'](DOWNLOAD['FIXTURE_REPO'], DOWNLOAD['FIXTURE_REVISION'])
    entries = {entry['rfilename']: entry for entry in metadata['siblings']}
    fixtures = []
    for name in DOWNLOAD['FIXTURE_FILES']:
        fixtures.append(DOWNLOAD['download_file'](target, 'fixtures/' + name,
            f"https://huggingface.co/{DOWNLOAD['FIXTURE_REPO']}/resolve/{DOWNLOAD['FIXTURE_REVISION']}/{name}", entries[name]))
    (target / 'fixture-manifest.json').write_text(json.dumps({'files': fixtures,
        'repository': DOWNLOAD['FIXTURE_REPO'], 'revision': DOWNLOAD['FIXTURE_REVISION'],
    }, indent=2), encoding='utf-8')
    print(f'Verified {len(rows)} model files and {len(fixtures)} public fixture files: {target}')


if __name__ == '__main__':
    main()
