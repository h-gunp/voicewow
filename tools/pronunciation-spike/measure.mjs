// Node WASM feasibility only: public fixtures and generated controls, no upload.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readWav } from '../prosody-web-tests/wav-fixture.mjs';

const root = fileURLToPath(new URL('../../.local/pronunciation-ipa/', import.meta.url));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function withinRoot(name) {
  if (!name || path.isAbsolute(name) || name.includes('\\') || name.includes(':')) throw new Error('Unsafe asset path');
  const target = path.resolve(root, name), relative = path.relative(root, target);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('Asset escapes local directory');
  return target;
}

async function loadAsset(asset) {
  const target = withinRoot(asset.path);
  const real = await fs.realpath(target);
  if (!real.startsWith((await fs.realpath(root)) + path.sep)) throw new Error('Asset symlink escapes local directory');
  const data = await fs.readFile(real);
  if (data.length !== asset.bytes || sha256(data) !== asset.sha256) throw new Error(`Asset integrity failure: ${asset.path}`);
  return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
}

function repeatTo(samples, length) {
  const result = new Float32Array(length);
  for (let offset = 0; offset < length; offset += samples.length) {
    result.set(samples.subarray(0, Math.min(samples.length, length - offset)), offset);
  }
  return result;
}

function noise(length) {
  let state = 1729;
  return Float32Array.from({ length }, () => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return (state / 2 ** 32 - .5) * .2;
  });
}

async function selfCheck() {
  for (const name of ['../outside', '/outside', 'C:/outside', 'a\\outside', '']) assert.throws(() => withinRoot(name));
  assert.deepEqual([...repeatTo(new Float32Array([1, 2]), 5)], [1, 2, 1, 2, 1]);
  assert.deepEqual(noise(10), noise(10));
  assert(noise(10).every(value => Number.isFinite(value) && Math.abs(value) <= .1));
  const temporary = '.measure-self-check';
  await fs.mkdir(root, { recursive: true });
  try {
    await fs.writeFile(path.join(root, temporary), 'safe');
    const asset = { path: temporary, bytes: 4, sha256: sha256('safe') };
    assert.equal((await loadAsset(asset)).length, 4);
    await assert.rejects(loadAsset({ ...asset, bytes: 3 }), /integrity/);
    await assert.rejects(loadAsset({ ...asset, sha256: '0'.repeat(64) }), /integrity/);
  } finally {
    await fs.unlink(path.join(root, temporary));
  }
  console.log('self-check passed: paths, fixture extension, deterministic noise, asset size/hash');
}

async function main() {
  const { createPhoneEngine } = await import('./phone-engine.mjs');
  const { env } = await import('../../apps/client/web/pronunciation/vendor/onnx/ort.wasm.min.mjs');
  const manifest = JSON.parse(await fs.readFile(path.join(root, 'model-manifest.json'), 'utf8'));
  const fixtureManifest = JSON.parse(await fs.readFile(path.join(root, 'fixture-manifest.json'), 'utf8'));
  const waves = [];
  for (const id of [0, 2]) {
    const relative = `fixtures/test_wavs/${id}.wav`;
    const entry = fixtureManifest.files.find(file => file.file === relative);
    if (!entry) throw new Error(`Missing fixture provenance: ${relative}`);
    await loadAsset({ ...entry, path: entry.file });
    const wave = readWav(path.join(root, relative));
    assert.equal(wave.sampleRate, 16000);
    waves.push({ ...wave, path: relative, sha256: entry.sha256 });
  }
  const report = {
    kind: 'Node single-thread WASM; public source fixtures and artificial controls; not browser/device or pronunciation-accuracy validation',
    timestamp: new Date().toISOString(), node: process.version, platform: process.platform, arch: process.arch,
    cpu: os.cpus()[0]?.model, logicalCpus: os.cpus().length, totalMemoryBytes: os.totalmem(), runtime: env.versions,
    model: { repository: manifest.repository, revision: manifest.revision,
      ...manifest.files.find(file => file.file === 'model.safetensors') },
    fixtureSource: fixtureManifest, memoryBeforeInit: process.memoryUsage(), results: [],
    accuracy: { assessed: false, reason: 'No human-verified correct/incorrect pronunciation recordings; source read-text is not an acoustic ground-truth label' },
    timingLimit: 'Single shared-machine run; warm-up, CPU contention and trial order are not controlled',
  };
  let engine;
  try {
    const start = performance.now();
    engine = await createPhoneEngine({ loadAsset });
    report.initMs = performance.now() - start;
    report.memoryAfterInit = process.memoryUsage();
    report.metadata = engine.metadata;
    const cases = [
      { id: 'public-0-first', ...waves[0], kind: 'public KSS-derived speech fixture' },
      { id: 'public-0-warm', ...waves[0], kind: 'same public fixture repeated for warm timing' },
      { id: 'public-2', ...waves[1], kind: 'public KSS-derived speech fixture' },
      { id: 'speech-prefix-5s', ...waves[1], samples: waves[1].samples.slice(0, 16000 * 5), kind: 'artificial 5-second prefix; not a complete natural utterance' },
      { id: 'speech-repeat-20s', ...waves[1], samples: repeatTo(waves[1].samples, 16000 * 20), kind: 'artificial concatenation to 20 seconds; capacity timing only' },
      { id: 'silence-1s', sampleRate: 16000, samples: new Float32Array(16000), kind: 'generated silence control' },
      { id: 'noise-5s', sampleRate: 16000, samples: noise(16000 * 5), kind: 'seeded white-noise control; not physical noise' },
    ];
    for (const item of cases) {
      const before = process.memoryUsage(), start = performance.now();
      let output, error;
      try { output = await engine.recognize(item.samples, item.sampleRate); }
      catch (failure) { error = { name: failure.name, message: failure.message }; }
      const computeMs = performance.now() - start, seconds = item.samples.length / item.sampleRate;
      const row = { id: item.id, kind: item.kind, sourcePath: item.path, sourceSha256: item.sha256,
        sampleRate: item.sampleRate, seconds, computeMs, realTimeFactor: computeMs / (seconds * 1000),
        memoryBefore: before, memoryAfter: process.memoryUsage(), output, error };
      if (error && item.id !== 'silence-1s') process.exitCode = 1;
      if (item.id === 'silence-1s' && !error) process.exitCode = 1;
      report.results.push(row);
      console.log(JSON.stringify({ id: row.id, seconds, computeMs, realTimeFactor: row.realTimeFactor, error,
        phones: output?.phones.map(phone => phone.phone), display: output?.display.text,
        uncertainOrthography: output?.display.uncertain }));
    }
  } catch (error) {
    report.fatalError = { name: error.name, message: error.message, stack: error.stack };
    process.exitCode = 1;
  } finally {
    await engine?.dispose();
    report.memoryAfterDispose = process.memoryUsage();
    report.processMaxRssKiB = process.resourceUsage().maxRSS;
    report.memoryLimit = 'RSS snapshots are before/after operations; OS maxRSS is process-wide, not isolated tensor memory';
    await fs.writeFile(path.join(root, 'node-report.json'), JSON.stringify(report, null, 2));
  }
  console.log(`Report: ${path.join(root, 'node-report.json')}`);
}

if (process.argv.includes('--self-check')) await selfCheck();
else await main();
