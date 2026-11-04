# Unmodified official browser runtime

Source: https://pub.dev/api/archives/sherpa_onnx_web-2.0.1.tar.gz
Archive SHA-256: 38dce9890b22227c4a18c35cd09205435efcad6bd3ef788f9065673385a967dc
Source repository/tag: https://github.com/k2-fsa/sherpa-onnx/tree/v2.0.1

The JS factory, ASR binding and WASM are unmodified. Apache-2.0 license and
dependency notices are alongside the files. These include ONNX Runtime 1.28.2,
kaldi-native-fbank 1.22.4, kaldi-decoder 0.3.0, OpenFst 1.8.5-2026-07-09,
simple-sentencepiece 0.7, utf8proc 2.12.0, nlohmann/json 3.12.0,
hclust-cpp 2026-02-25 and Eigen 5.0.1. Build dependency sources/versions:
https://github.com/k2-fsa/sherpa-onnx/tree/v2.0.1/cmake
Unmodified Eigen source: https://gitlab.com/libeigen/eigen/-/tree/5.0.1

Model weights are not bundled. The worker GETs the pinned Korean conversion
directly from Hugging Face and verifies byte sizes/SHA-256. Original model card
declares Apache-2.0; the conversion card links to it, without a separate license
declaration. Both cards are retained for provenance. No training dataset or
public test WAV is distributed with the feature. This does not establish
separate redistribution rights for those samples.

Recognition runs locally after model loading. There is no remote ASR fallback.
See docs/wasm-asr-feasibility.md in the repository for measurements and limits.
