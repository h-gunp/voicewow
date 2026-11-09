import * as ort from './vendor/onnx/ort.wasm.min.mjs';
import { prepareSamples, decodePhones, phonesToHangul } from './phones.mjs';
import { sha256 } from './sha256.mjs';
import { ipaToPhones } from './ipa-phones.mjs';

export const MODEL_REVISION = '772950d64427910937e11c5b76c9e4594059ce8c';
export const MODEL_ASSETS = Object.freeze([
  {
    "path": "config.json",
    "bytes": 2369,
    "sha256": "fabc5f4a4238971ae1399ca5f3e591ae5beb142fdd2b3804a20e6700649ea83e"
  },
  {
    "path": "vocab.json",
    "bytes": 645,
    "sha256": "7027b570bda6e7ea7a3b3b44f1e8198e2d521f9b57a7857579ac7001e0cb72f1"
  },
  {
    "path": "added_tokens.json",
    "bytes": 30,
    "sha256": "843da62c8cdea9fb78b7303dc873d0988c7debf7e1c9903e8dfd22c1705f31a2"
  },
  {
    "path": "preprocessor_config.json",
    "bytes": 258,
    "sha256": "3698647300e38b0a83ccf0ee9b24834e2d262157410305d54a3a1f655ead3002"
  },
  {
    "path": "ko-ipa.onnx",
    "bytes": 282052,
    "sha256": "840b1a2f19d1b2c52ac5ef522764d5e5fb42ad79a0b839805904ed1b6b36f949"
  },
  {
    "path": "model.safetensors",
    "bytes": 377681876,
    "sha256": "dfe465932554b8d8d5ff818afb27995fc7ac20e6af7e3b77f26a8aa7e7dc0404"
  }
].map(Object.freeze));
export const WEB_MODEL_ASSET = MODEL_ASSETS[4];

export async function createPhoneEngine({ loadAsset, modelAsset = MODEL_ASSETS[4], onProgress = () => {} }) {
  const read = async asset => {
    const bytes = await loadAsset(asset);
    if (!(bytes instanceof ArrayBuffer) && !(bytes instanceof Uint8Array)) throw new Error('모델 파일 형식이 올바르지 않다.');
    if (bytes.byteLength !== asset.bytes) throw new Error('모델 파일 크기가 올바르지 않다.');
    const hash = await sha256(bytes);
    if (hash !== asset.sha256) throw new Error('모델 파일 해시가 일치하지 않는다. 다시 내려받아야 한다.');
    return bytes;
  };
  const json = async index => JSON.parse(new TextDecoder().decode(await read(MODEL_ASSETS[index])));
  const config = await json(0), vocab = { ...await json(1), ...await json(2) }, processor = await json(3);
  if (config.vocab_size !== 55 || config.pad_token_id !== 0 || Object.keys(vocab).length !== 55
    || processor.sampling_rate !== 16000 || processor.do_normalize !== false) throw new Error('지원하지 않는 음소 모델 설정이다.');
  ort.env.wasm.numThreads = 1;
  ort.env.wasm.proxy = false;
  ort.env.wasm.wasmPaths = new URL('../prosody/vendor/onnx/', import.meta.url).href;
  ort.env.logLevel = 'error';
  const modelBytes = await read(modelAsset);
  const weights = await read(MODEL_ASSETS[5]);
  onProgress('다운로드와 검증을 마쳤다. 기기 안에서 발음 모델을 여는 중이다.');
  const session = await ort.InferenceSession.create(modelBytes, {
    // Graph optimization adds a large allocation while the mobile session opens.
    executionProviders: ['wasm'], graphOptimizationLevel: 'disabled',
    externalData: [{ path: 'model.safetensors', data: weights }],
  });
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
        return { phones, display: phonesToHangul(ipaToPhones(phones)), inferenceMs: performance.now() - start,
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
