import * as ort from '../prosody/vendor/onnx/ort.wasm.min.mjs';
import { prepareSamples, decodePhones, phonesToHangul } from './phones.mjs';

export const MODEL_REVISION = 'dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70';
export const MODEL_ASSETS = Object.freeze([
  { path: 'config.json', bytes: 2063, sha256: 'bc3394c2db0f96a9ab5e68c3a389201266bd21a26fcde109ff9d07accda26bd2' },
  { path: 'vocab.json', bytes: 500, sha256: 'ca2a65143ce6acf25913f7e354ca7bae767ddb39b99218713057ae117dc87fc9' },
  { path: 'added_tokens.json', bytes: 30, sha256: 'e6fbfcadb18a959fef9b7736b9f23fa2f5761674824f0db1263aaaf2e15e0959' },
  { path: 'preprocessor_config.json', bytes: 279, sha256: 'f6a6867d632ee397cab2eb1c6a49dc64d857bb085e0f0463705b0217f4b96da4' },
  { path: 'onnx/model_quantized.onnx', bytes: 356129122, sha256: 'c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134' },
]);

export async function createPhoneEngine({ loadAsset }) {
  const read = async asset => {
    const bytes = await loadAsset(asset);
    if (!(bytes instanceof ArrayBuffer) && !(bytes instanceof Uint8Array)) throw new Error('모델 파일 형식이 올바르지 않다.');
    if (bytes.byteLength !== asset.bytes) throw new Error('모델 파일 크기가 올바르지 않다.');
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
    if (hash !== asset.sha256) throw new Error('모델 파일 해시가 일치하지 않는다. 다시 내려받아야 한다.');
    return bytes;
  };
  const json = async index => JSON.parse(new TextDecoder().decode(await read(MODEL_ASSETS[index])));
  const config = await json(0), vocab = { ...await json(1), ...await json(2) }, processor = await json(3);
  if (config.vocab_size !== 45 || config.pad_token_id !== 42 || Object.keys(vocab).length !== 45
    || processor.sampling_rate !== 16000 || processor.do_normalize !== true) throw new Error('지원하지 않는 음소 모델 설정이다.');
  ort.env.wasm.numThreads = 1;
  ort.env.wasm.proxy = false;
  ort.env.wasm.wasmPaths = new URL('../prosody/vendor/onnx/', import.meta.url).href;
  ort.env.logLevel = 'error';
  const session = await ort.InferenceSession.create(await read(MODEL_ASSETS[4]), { executionProviders: ['wasm'], graphOptimizationLevel: 'all' });
  const metadata = { inputs: session.inputMetadata, outputs: session.outputMetadata, versions: ort.env.versions };
  if (session.inputNames.length !== 1 || session.inputNames[0] !== 'input_values' || session.outputNames[0] !== 'logits') {
    await session.release(); throw new Error('지원하지 않는 음소 모델 입출력이다.');
  }
  let busy = false, disposed = false;
  return {
    metadata,
    async recognize(samples, sampleRate) {
      if (disposed || busy) throw new Error('분석기가 사용 중이거나 종료됐다.');
      const normalized = prepareSamples(samples, sampleRate);
      busy = true;
      const tensor = new ort.Tensor('float32', normalized, [1, normalized.length]);
      const start = performance.now();
      let output;
      try {
        output = await session.run({ input_values: tensor });
        const phones = decodePhones(output.logits.data, output.logits.dims, vocab);
        return { phones, display: phonesToHangul(phones), inferenceMs: performance.now() - start,
          duration: samples.length / sampleRate, frames: output.logits.dims[1] };
      } finally {
        tensor.dispose();
        for (const value of Object.values(output ?? {})) value.dispose();
        busy = false;
      }
    },
    async dispose() {
      if (busy) throw new Error('분석 중에는 워커를 종료해 취소해야 한다.');
      if (!disposed) { disposed = true; await session.release(); }
    },
  };
}
