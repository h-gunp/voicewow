import { readFileSync } from 'node:fs';
export function readWav(path) {
  const file = readFileSync(path);
  let sampleRate, channels, bits, data;
  for (let at = 12; at + 8 <= file.length;) {
    const type = file.toString('ascii', at, at + 4), size = file.readUInt32LE(at + 4);
    if (type === 'fmt ') {
      if (file.readUInt16LE(at + 8) !== 1) throw new Error('PCM WAV required');
      channels = file.readUInt16LE(at + 10); sampleRate = file.readUInt32LE(at + 12); bits = file.readUInt16LE(at + 22);
    }
    if (type === 'data') data = file.subarray(at + 8, at + 8 + size);
    at += 8 + size + size % 2;
  }
  if (bits !== 16 || !data?.length) throw new Error('16-bit WAV with sound required');
  const samples = new Float32Array(data.length / (2 * channels));
  for (let i = 0; i < samples.length; i++) for (let c = 0; c < channels; c++) samples[i] += data.readInt16LE((i * channels + c) * 2) / (32768 * channels);
  return { samples, sampleRate };
}
