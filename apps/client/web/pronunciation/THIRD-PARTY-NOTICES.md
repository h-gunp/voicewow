# Current Korean IPA model

VoiceMate downloads the original [icig/normal-korean-ipa-translation](https://huggingface.co/icig/normal-korean-ipa-translation/tree/772950d64427910937e11c5b76c9e4594059ce8c) safetensors file directly from its pinned upstream revision. Audio and recognition results remain on the device.

- Model: Wav2Vec2 base, 94.4M parameters, 55 CTC classes, blank 0, separator 51.
- Input: raw mono 16kHz float32; the upstream processor disables normalization and attention masks.
- Weights: 377,681,876 bytes; SHA-256 `dfe465932554b8d8d5ff818afb27995fc7ac20e6af7e3b77f26a8aa7e7dc0404`.
- `models/ko-ipa.onnx` contains the graph and operator constants, with zero embedded learned initializer bytes. All 212 learned initializers reference byte ranges in the original `model.safetensors`. No converted weights are hosted by this repository or Sites.
- Graph: 282,052 bytes; SHA-256 `840b1a2f19d1b2c52ac5ef522764d5e5fb42ad79a0b839805904ed1b6b36f949`.
- Exact source URLs, tensor offsets, hashes and export versions are in `models/source.json`. Reproduction: `tools/pronunciation-spike/export-ipa-model.py`.
- Upstream has no declared license in its repository or API metadata. The earlier model's Apache-2.0 license does not describe this new checkpoint. No permission grant is inferred from public availability.
- Runtime remains ONNX Runtime Web/Android 1.23.2. The notices below retain the previous model and the unchanged vendored runtime's provenance.

## Previous MFA model (historical)


The application downloads public model assets; microphone audio and recognition results are not uploaded.

- ONNX conversion: [chegrowk/ko-phone-int8](https://huggingface.co/chegrowk/ko-phone-int8/tree/dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70), revision `dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70`.
- Original model: [slplab/wav2vec2-xls-r-300m_phone-mfa_korean](https://huggingface.co/slplab/wav2vec2-xls-r-300m_phone-mfa_korean/tree/e26ff9dfb62169acf445d0060ef56863c018b20e), revision `e26ff9dfb62169acf445d0060ef56863c018b20e`.
- Both pinned model cards declare Apache-2.0. The downloaded conversion's license is included in `LICENSE-model.txt`.
- The conversion author describes ONNX opset 17 and dynamic per-channel int8 quantization of MatMul. This application uses the converted assets without modifying model weights.
- Weight file: 356,129,122 bytes; SHA-256 `c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134`. Configuration and vocabulary hashes are fixed in `phone-engine.mjs`.
- 발음 기능은 ONNX Runtime Web 1.23.2의 전용 JS 런타임인 `vendor/onnx/ort.wasm.min.mjs`를 사용한다. 수정하지 않은 WASM 모듈·바이너리는 `../prosody/vendor/onnx/`에서 공유하며 기존 라이선스와 제3자 고지는 해당 디렉터리에 남아 있다.

Original-work citation from the conversion card: Yeo, E., Ryu, H., Lee, J., Kim, S., & Chung, M. (2023). Comparison of L2 Korean pronunciation error patterns from five L1 backgrounds by using automatic phonetic transcription. Proceedings of the 20th International Congress of Phonetic Sciences, pp. 2696–2700.

The original model's reported metric is not VoiceMate accuracy. Browser/device performance and pronunciation accuracy require separate validation.

## 웹 ORT 산출물과 런타임 출처

제품 웹의 `ko-phone-int8.ort`는 위 고정 ONNX 가중치를 Python ONNX Runtime 1.31.0의 extended 최적화로 직렬화한 파일이다. 추가 양자화나 학습은 하지 않았다. 크기는 356,216,776바이트이고 SHA-256은 `a280f2679f08c809ae3c5ad55abe15dc78803e06143cc9b485c143612652765e`다. 기존 모델의 Apache-2.0 고지와 원저자 표기를 유지한다.

이 고정 파일은 `ko-phone-int8.ort.part00`부터 `.part21`까지 16MiB 이하의 22개 조각으로 GitHub `h-gunp/voicewow`의 모델 자산 전용 브랜치에 게시하며, 브라우저는 `raw.githubusercontent.com`의 고정 커밋 URL에서 받는다. Sites 앱 배포에는 모델 조각을 포함하지 않는다. 공개 모델 파일을 받는 요청이며 사용자 음성·문장·인식 결과를 전송하지 않는다. `tools/pronunciation-spike/prepare-web-model.py`는 선택적인 로컬 검증·캐시 준비 도구이며 전체 크기·결합 해시를 검증한다. 기본 spike와 Android는 기존 ONNX 파일을 사용한다.

모델 자산 브랜치는 `codex/pronunciation-model-ort-a280f267`이며 다운로드 기준은 [커밋 `72bb26aa05c94763dfab5f150a7ae747a1937e10`](https://github.com/h-gunp/voicewow/tree/72bb26aa05c94763dfab5f150a7ae747a1937e10)이다. [첫 모델 조각](https://raw.githubusercontent.com/h-gunp/voicewow/72bb26aa05c94763dfab5f150a7ae747a1937e10/ko-phone-int8.ort.part00), [모델 출처 기록](https://raw.githubusercontent.com/h-gunp/voicewow/72bb26aa05c94763dfab5f150a7ae747a1937e10/source.json), [모델 라이선스](https://raw.githubusercontent.com/h-gunp/voicewow/72bb26aa05c94763dfab5f150a7ae747a1937e10/LICENSE)는 모두 이 고정 커밋을 사용한다.

발음 전용 JS 런타임의 upstream은 [onnxruntime-web 1.23.2 배포 파일](https://cdn.jsdelivr.net/npm/onnxruntime-web@1.23.2/dist/ort.wasm.min.mjs)과 [WASM 세션 구현](https://github.com/microsoft/onnxruntime/blob/v1.23.2/js/web/lib/wasm/wasm-core-impl.ts)이다. MIT 라이선스는 `vendor/onnx/LICENSE.txt`, 원본·수정본 해시와 패치 범위는 `vendor/onnx/source.json`에 있다. 원본 JS의 SHA-256은 `69751720f611e37d1ce2fa3c6ebaa80f949014752636c5f8887a63d40feadcc7`, 수정본은 `583c6a7bae7abc378c8c74087e84017f36d59a537dc572769ac34af0fb122d63`다.

`tools/pronunciation-spike/patch-runtime.mjs`가 이 전용 런타임을 재현한다. 패치는 직접 참조하는 WASM 모델 버퍼를 세션 종료까지 보존하고 한 번만 해제하며, 명시적으로 소유권을 넘긴 전체 입력 버퍼는 지원 환경에서 WASM 복사 뒤 detach한다. 일반 세션의 즉시 해제 경로와 공유 WASM 바이너리는 유지한다. 부분 뷰·공유 버퍼·미지원 환경에는 입력 해제를 적용하지 않는다. 로컬 공개 WAV 결과 일치와 메모리 측정은 실제 브라우저·기기·발음 정확도 검증과 구분한다.

## Bounded-memory integrity checks

`vendor/hash-wasm/sha256.umd.min.js` is the unmodified SHA-256 bundle from hash-wasm 4.12.0 (MIT), https://github.com/Daninet/hash-wasm. The npm tarball integrity and vendored file SHA-256 values are recorded in `vendor/hash-wasm/source.json`; the license is adjacent. It replaces whole-buffer WebCrypto hashing with incremental hashing and requires no external script request at runtime.
