function validate(samples, sampleRate) {
  if (!(samples instanceof Float32Array) || !samples.length || !Number.isInteger(sampleRate)
    || sampleRate < 8000 || sampleRate > 192000 || samples.length > sampleRate * 20
    || samples.some(value => !Number.isFinite(value) || Math.abs(value) > 1.001)) throw new Error('20초 이하의 유효한 오디오가 필요하다.');
}

// Match native PracticeDownsampler: 7.2kHz low-pass, centered 63-tap Hamming FIR.
const downsampleTaps = Float32Array.from({length: 63}, (_, index) => {
  const x = index - 31;
  const lowpass = x === 0 ? .3 : Math.sin(2 * Math.PI * .15 * x) / (Math.PI * x);
  return lowpass * (.54 - .46 * Math.cos(2 * Math.PI * index / 62));
});
let tapSum = 0;
for (const tap of downsampleTaps) tapSum = Math.fround(tapSum + tap);
for (let i = 0; i < downsampleTaps.length; i++) downsampleTaps[i] /= tapSum;

function downsample48kHz(samples) {
  const result = new Float32Array(Math.ceil(samples.length / 3));
  for (let i = 0; i < result.length; i++) {
    let value = 0;
    for (let tap = 0; tap < downsampleTaps.length; tap++) {
      const index = i * 3 + 31 - tap;
      if (index >= 0 && index < samples.length) value += Math.fround(downsampleTaps[tap] * samples[index]);
    }
    result[i] = Math.max(-1, Math.min(1, value));
  }
  return result;
}

export async function to16kHz(samples, sampleRate) {
  validate(samples, sampleRate);
  if (sampleRate === 16000) return samples.slice();
  if (sampleRate === 48000) return downsample48kHz(samples);
  const Context = globalThis.OfflineAudioContext || globalThis.webkitOfflineAudioContext;
  if (!Context) throw new Error('이 브라우저에서 오디오 변환을 사용할 수 없다.');
  const context = new Context(1, Math.round(samples.length / sampleRate * 16000), 16000);
  const buffer = context.createBuffer(1, samples.length, sampleRate);
  buffer.copyToChannel(samples, 0);
  const source = context.createBufferSource(); source.buffer = buffer;
  source.connect(context.destination); source.start();
  const result = (await context.startRendering()).getChannelData(0).slice();
  // Resampling can overshoot around full-scale edges; retain normalized PCM.
  for (let i = 0; i < result.length; i++) if (Number.isFinite(result[i])) result[i] = Math.max(-1, Math.min(1, result[i]));
  validate(result, 16000);
  return result;
}

export function encodeWav(samples, sampleRate) {
  validate(samples, sampleRate);
  const buffer = new ArrayBuffer(44 + samples.length * 2), view = new DataView(buffer);
  const text = (offset, value) => { for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i)); };
  text(0, 'RIFF'); view.setUint32(4, buffer.byteLength - 8, true); text(8, 'WAVE'); text(12, 'fmt ');
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true); view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true); view.setUint16(34, 16, true); text(36, 'data'); view.setUint32(40, samples.length * 2, true);
  samples.forEach((value, i) => view.setInt16(44 + i * 2, Math.round(Math.max(-1, Math.min(1, value)) * (value < 0 ? 32768 : 32767)), true));
  return buffer;
}

export function decodeWav(buffer) {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength < 44 || buffer.byteLength > 16000000) throw new Error('20초 이하의 16비트 PCM WAV 파일이 필요하다.');
  const view = new DataView(buffer), text = at => String.fromCharCode(...new Uint8Array(buffer, at, 4));
  if (text(0) !== 'RIFF' || text(8) !== 'WAVE' || view.getUint32(4, true) + 8 !== buffer.byteLength) throw new Error('WAV 파일이 완전하지 않다.');
  let rate, channels, data, dataSize;
  for (let at = 12; at + 8 <= buffer.byteLength;) {
    const size = view.getUint32(at + 4, true), end = at + 8 + size;
    if (end > buffer.byteLength) throw new Error('WAV 파일이 완전하지 않다.');
    if (text(at) === 'fmt ') {
      if (size < 16 || rate !== undefined || view.getUint16(at + 8, true) !== 1 || view.getUint16(at + 22, true) !== 16) throw new Error('16비트 PCM WAV만 지원한다.');
      channels = view.getUint16(at + 10, true); rate = view.getUint32(at + 12, true);
      if (![1, 2].includes(channels) || view.getUint16(at + 20, true) !== channels * 2) throw new Error('모노 또는 스테레오 WAV가 필요하다.');
    }
    if (text(at) === 'data') {
      if (data !== undefined) throw new Error('중복된 WAV 데이터다.');
      data = at + 8; dataSize = size;
    }
    at = end + size % 2;
  }
  if (!rate || data === undefined || !dataSize || dataSize % (channels * 2) !== 0 || dataSize / (channels * 2) > rate * 20) throw new Error('20초 이하의 WAV 오디오가 필요하다.');
  const samples = new Float32Array(dataSize / (channels * 2));
  for (let i = 0; i < samples.length; i++) for (let c = 0; c < channels; c++) samples[i] += view.getInt16(data + (i * channels + c) * 2, true) / (32768 * channels);
  validate(samples, rate);
  return { samples, sampleRate: rate };
}
