// VoiceMate integration of the MIT-licensed Supertonic reference implementation.
// Model inference produces a reading example, not an assessment or normative target.
import * as ort from '../onnx/ort.wasm.min.mjs';
import { UnicodeProcessor, TextToSpeech, Style } from './helper.js';

export const MODEL_REVISION = 'aafc6e32416a594460b32413efc49d7fe4ce6d46';
export const MODEL_BASE = `https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/${MODEL_REVISION}/`;
export const MODEL_ASSETS = Object.freeze([
  { path: 'onnx/tts.json', bytes: 8253 },
  { path: 'onnx/unicode_indexer.json', bytes: 277676 },
  { path: 'voice_styles/F3.json', bytes: 290794 },
  { path: 'onnx/duration_predictor.onnx', bytes: 3700147 },
  { path: 'onnx/text_encoder.onnx', bytes: 36416150 },
  { path: 'onnx/vector_estimator.onnx', bytes: 256534781 },
  { path: 'onnx/vocoder.onnx', bytes: 101424195 },
]);
export const MODEL_DOWNLOAD_BYTES = MODEL_ASSETS.reduce((sum, asset) => sum + asset.bytes, 0);
export const GUIDE_SOURCE = 'AI 읽기 예시 · Supertonic 3';
export const MAX_GUIDE_CHARACTERS = 100;
export const MAX_GUIDE_SECONDS = 20;

export function validateGuideText(text) {
  if (typeof text !== 'string' || !text.trim()) throw new Error('가이드를 만들 문장을 먼저 입력해 주세요.');
  if (Array.from(text.trim()).length > MAX_GUIDE_CHARACTERS) throw new Error('한 번에 100자 이하의 문장으로 가이드를 만들어 주세요.');
  return text.trim();
}

/** The injected loader may read public model assets from HTTP/cache or test disk.
 * It never receives the script or a user recording. Retain the returned engine
 * between sentences; four sessions share one worker and are loaded only once.
 */
export async function createSpeechEngine({ loadAsset, onProgress = () => {} }) {
  ort.env.wasm.numThreads = 1;
  ort.env.wasm.proxy = false;
  ort.env.wasm.wasmPaths = new URL('../onnx/', import.meta.url).href;
  ort.env.logLevel = 'error';
  const decoder = new TextDecoder();
  const json = async path => JSON.parse(decoder.decode(await loadAsset(MODEL_ASSETS.find(asset => asset.path === path))));
  const cfgs = await json('onnx/tts.json');
  const indexer = await json('onnx/unicode_indexer.json');
  const voice = await json('voice_styles/F3.json');
  const sessions = [];
  try {
    for (const asset of MODEL_ASSETS.filter(asset => asset.path.endsWith('.onnx'))) {
      const bytes = await loadAsset(asset);
      onProgress({ phase: 'initializing', message: `가이드 준비 중 · 음성 엔진 ${sessions.length + 1}/4` });
      sessions.push(await ort.InferenceSession.create(bytes, {
        executionProviders: ['wasm'], graphOptimizationLevel: 'all',
      }));
    }
    const style = new Style(
      new ort.Tensor('float32', Float32Array.from(voice.style_ttl.data.flat(Infinity)), voice.style_ttl.dims),
      new ort.Tensor('float32', Float32Array.from(voice.style_dp.data.flat(Infinity)), voice.style_dp.dims),
    );
    const tts = new TextToSpeech(cfgs, new UnicodeProcessor(indexer), ...sessions);
    return {
      async generate(text, progress = () => {}) {
        const sentence = validateGuideText(text);
        progress({ phase: 'synthesizing', message: '입력한 문장의 AI 읽기 예시를 만들고 있어요.' });
        const { wav, duration } = await tts.call(sentence, 'ko', style, 8, 1.0, 0.3,
          (step, steps) => progress({ phase: 'synthesizing', message: `AI 읽기 예시 생성 중 · ${step}/${steps}`, step, steps }));
        const seconds = duration?.[0];
        if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('가이드 음성을 만들지 못했어요. 문장을 조금 줄여 다시 시도해 주세요.');
        if (seconds > MAX_GUIDE_SECONDS) throw new Error('가이드 음성이 20초를 넘어요. 문장을 더 짧게 나눠 주세요.');
        const samples = Float32Array.from(wav.slice(0, Math.floor(tts.sampleRate * seconds)));
        if (!samples.length || samples.some(value => !Number.isFinite(value))) throw new Error('가이드 음성 생성 중 문제가 생겼어요. 다시 시도해 주세요.');
        return { samples, sampleRate: tts.sampleRate, source: GUIDE_SOURCE };
      },
      async dispose() {
        style.ttl.dispose(); style.dp.dispose();
        await Promise.all(sessions.map(session => session.release()));
      },
    };
  } catch (error) {
    await Promise.allSettled(sessions.map(session => session.release()));
    throw error;
  }
}
