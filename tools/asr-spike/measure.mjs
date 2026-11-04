// Native Windows feasibility measurement ONLY. Not a browser/Safari benchmark.
// Reads public local WAV fixtures. No network requests, microphone or upload.
import sherpa from 'sherpa-onnx-node';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { alignFinal } from './alignment.mjs';
const root = fileURLToPath(new URL('../../.local/asr-spike/', import.meta.url));
const t0 = performance.now();
const recognizer = new sherpa.OnlineRecognizer({
  featConfig: { sampleRate: 16000, featureDim: 80 },
  modelConfig: {
    transducer: {
      encoder: path.join(root, 'encoder-epoch-99-avg-1.int8.onnx'),
      decoder: path.join(root, 'decoder-epoch-99-avg-1.onnx'),
      joiner: path.join(root, 'joiner-epoch-99-avg-1.int8.onnx'),
    }, tokens: path.join(root, 'tokens.txt'), numThreads: 1, provider: 'cpu',
  }, decodingMethod: 'greedy_search', enableEndpoint: true,
});
const initMs = performance.now() - t0;
const transcripts = fs.readFileSync(path.join(root, 'test_wavs/trans.txt'), 'utf8').trim().split('\n');
const results = [];
let peakRss = process.memoryUsage().rss;
for (let i = 0; i < 4; i++) {
  const wave = sherpa.readWave(path.join(root, `test_wavs/${i}.wav`));
  const stream = recognizer.createStream();
  const duration = wave.samples.length / wave.sampleRate;
  const chunkSize = Math.round(0.16 * wave.sampleRate);
  const steps = [], changes = [];
  let previous = '', firstEvidenceSeconds = null;
  const begin = performance.now();
  for (let offset = 0; offset < wave.samples.length; offset += chunkSize) {
    const start = performance.now();
    stream.acceptWaveform({ sampleRate: wave.sampleRate, samples: wave.samples.slice(offset, offset + chunkSize) });
    while (recognizer.isReady(stream)) recognizer.decode(stream);
    steps.push(performance.now() - start);
    const result = recognizer.getResult(stream);
    if (result.text !== previous) {
      const inputSeconds = Math.min(offset + chunkSize, wave.samples.length) / wave.sampleRate;
      changes.push({ inputSeconds, text: result.text });
      if (result.text && firstEvidenceSeconds === null) firstEvidenceSeconds = inputSeconds;
      previous = result.text;
    }
    peakRss = Math.max(peakRss, process.memoryUsage().rss);
  }
  stream.acceptWaveform({ sampleRate: wave.sampleRate, samples: new Float32Array(wave.sampleRate * 0.5) });
  stream.inputFinished();
  while (recognizer.isReady(stream)) recognizer.decode(stream);
  const final = recognizer.getResult(stream);
  const computeMs = performance.now() - begin;
  const reference = transcripts[i].replace(/^\S+\s+/, '').trim();
  steps.sort((a,b) => a-b);
  results.push({ sample:i, seconds:duration, computeMs, realTimeFactor:computeMs / (duration * 1000),
    firstEvidenceInputSeconds:firstEvidenceSeconds, p95ChunkComputeMs:steps[Math.floor(steps.length * 0.95)],
    maxChunkComputeMs:Math.max(...steps), final, reference,
    alignment:alignFinal(reference, final.text, {final:true}), changes });
}
const report = { kind:'native-only public-fixture spike', runtime:sherpa.version, runtimeCommit:sherpa.gitSha1,
  node:process.version, platform:process.platform, arch:process.arch, cpu:os.cpus()[0].model,
  initMs, sampledPeakRssBytes:peakRss, processMaxRssKiB:process.resourceUsage().maxRSS, results };
fs.writeFileSync(path.join(root, 'native-report.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
