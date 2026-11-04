# Korean streaming ASR: browser runtime handoff

2026-11-04. No browser automation, microphone access, or user-audio upload was
performed. These tests execute WASM under Node, including the actual application
worker source in a VM with fixed local-file GET shims. They are not Safari tests.

## Ready-to-use official browser artifacts

Official package: `sherpa_onnx_web` 2.0.1, published from the sherpa-onnx project.

- Archive: https://pub.dev/api/archives/sherpa_onnx_web-2.0.1.tar.gz
- Registry metadata: https://pub.dev/api/packages/sherpa_onnx_web
- Verified archive SHA-256: `38dce9890b22227c4a18c35cd09205435efcad6bd3ef788f9065673385a967dc`
- Compressed archive: 4,341,646 bytes.
- JS glue: 93,272 bytes, SHA `8200e26b659643104cd460b57cc7e1b33129bf20ef791331017da14d04794e99`.
- WASM: 15,203,590 bytes, SHA `43fab086ecec5365ebee028bf3982c0336a923eca879757f6fe8329f863dabf6`.
- ASR binding: 54,712 bytes, SHA `fff0b2059f4e203d8d3c9fc4af997d146e724236c081b9f5af1e5df05c5a421b`.
- Runtime + ASR binding total: 15,351,574 bytes, excluding models and notices.

Extracted files and all collected notices are in `browser-runtime/`.
`runtime-manifest.json` records their byte sizes and digests. No package code was
modified. The official package is normally consumed through `sherpa_onnx` Dart;
using its unmodified JS/WASM directly uses the same published factory/bindings.

Pin source references to v2.0.1:

- https://github.com/k2-fsa/sherpa-onnx/blob/v2.0.1/wasm/web/CMakeLists.txt
- https://github.com/k2-fsa/sherpa-onnx/blob/v2.0.1/wasm/wasm-common.cmake
- https://github.com/k2-fsa/sherpa-onnx/blob/v2.0.1/build-wasm-simd-web.sh
- https://github.com/k2-fsa/sherpa-onnx/blob/v2.0.1/flutter/sherpa_onnx_web/lib/sherpa_onnx_web.dart

The generic browser target avoids the Node-only `NODERAWFS=1` flag. The npm
`sherpa-onnx` package is WASM but its Node filesystem wrapper must NOT be shipped
as a browser runtime. `sherpa-onnx-node` is native, not WASM. No Emscripten install
is needed to use the verified published browser assets; rebuilding would use the
official web script and Emscripten 4.0.23.

## Worker interface actually exercised

Classic worker `importScripts` can load the web glue and ASR wrapper. Then:

```
const module = await SherpaOnnx({ locateFile: name => fixedLocalURL(name) });
module.FS.writeFile('/encoder.onnx', verifiedEncoderBytes);
// Likewise decoder, joiner and tokens; config uses these MEMFS paths.
const recognizer = createOnlineRecognizer(module, config);
const stream = recognizer.createStream();
stream.acceptWaveform(sampleRate, float32MonoSamples);
while (recognizer.isReady(stream)) recognizer.decode(stream);
const result = recognizer.getResult(stream);
if (recognizer.isEndpoint(stream)) recognizer.reset(stream);
// Stop/cleanup:
stream.free(); recognizer.free();
```

`getResult()` returns text, token pieces and token timestamps. A piece may contain
multiple letters. Do not split that timestamp into invented letter times.
The caller must explicitly handle EOF/stop; 0.5 seconds of zeros plus
`inputFinished()` did not necessarily produce the same stabilized endpoint text
as continued streaming through silence in these samples.

The application's `asr-worker.js` successfully initialized with actual browser
WASM, processed all four public fixtures, emitted endpoint results, and rejected
a reused audio sequence number. The shim observed exactly five GETs: one local
WASM and the four pinned public model files. No script/audio network operation.
See `measure-application-worker.cjs` and `application-worker-report.json`.

## Actual desktop measurements (one run each)

Same public 4-WAV fixture set, Windows i5-13400F, Node 24.16.0, single-thread CPU,
runtime 2.0.1 `af2d8d81`, ONNX Runtime 1.28.2. No paced microphone input.

| Path | Initialization | Compute/audio ratio | Memory |
| --- | --- | --- | --- |
| Native (parent evidence) | 1.407s | .055–.059 | peak RSS 265.16 MiB |
| npm Node WASM | module .048s + recognizer 1.093s | .127–.156 | heap 512 MiB; peak RSS 369.57 MiB |
| Browser artifact, Node MEMFS | module .040s + copies .045s + recognizer 1.053s | .128–.158 | heap 512 MiB; sampled RSS ~518 MiB |
| Actual app worker, Node VM | 1.403s including local model shim | not directly comparable: extra endpoint silence | peak RSS ~809 MiB |

Browser-artifact 160ms chunk p95 compute was 39.6–44.7ms, max 81.4ms. VM/Response
copies inflate the orchestration measurement; none of these figures establish
mobile peak memory or microphone-to-screen latency. All 4 final outputs matched
the native EOF harness when the same 0.5-second EOF procedure was used.

With the application worker and 2.24 seconds of streamed silence, sample 1 became
`지하철에서다리를벌리고앉지마라.` and sample 2 matched the reference apart from spacing.
The earlier harness ended with erroneous words in those samples. Sample 0 still
had colloquial/substitution differences. This is evidence that endpoint handling
affects apparent accuracy; it is not a reason to force alignment to the reference.

`recognizer.free()` does not shrink the 512 MiB linear memory. Separate test
`measure-browser-artifact-unlink.cjs` removed the model MEMFS files after creating
the recognizer: all four fixtures still decoded, but immediate sampled RSS did
not materially shrink. Use worker termination for lifecycle isolation; do not
promise immediate browser reclamation. Real TTS→ASR→TTS/device tests remain needed.

## License/provenance deliverables

`browser-runtime/LICENSE` is the official package Apache-2.0 license. Other files
were collected from pinned dependency versions used by the v2.0.1 build:

- ONNX Runtime 1.28.2: MIT license + full upstream ThirdPartyNotices.
- kaldi-native-fbank 1.22.4 and kaldi-decoder 0.3.0: Apache-2.0 licenses.
- OpenFst 1.8.5-2026-07-09: Apache-2.0 notice (retain main Apache license too).
- simple-sentencepiece 0.7: Apache-2.0 license.
- utf8proc 2.12.0: MIT and included Unicode notices in its license file.
- nlohmann/json 3.12.0: complete upstream license page, including embedded code notices.
- hclust-cpp 2026-02-25: BSD redistribution notice.
- Eigen 5.0.1: MPL-2.0 text. Unmodified Eigen source remains available at
  https://gitlab.com/libeigen/eigen/-/tree/5.0.1; retain this source link with notices.

Version evidence is in the official `cmake/*.cmake` files at v2.0.1. Retain these
notices alongside vendored binary/JS, including attribution and source links;
do not treat the sherpa top-level license alone as the entire dependency notice.
This collected set is based on the published build dependencies, not a claim of
an independently reconstructed full binary SBOM.

Model provenance: `MODEL-ORIGINAL-CARD.md` explicitly declares `license: apache-2.0`.
`MODEL-CONVERSION-CARD.md` identifies that original as the source of the converted
Korean model. The converted repository has no separate LICENSE declaration. This
supports an Apache provenance chain, but do not invent a separate grant from the
converter. Include the Apache text and original/conversion attribution if models
are bundled; do not bundle the training dataset or public WAV samples based on a
model license. Current feature can GET pinned model assets directly, with no user
data in URLs. Sample redistribution rights are separate and not established here.

## Safari boundary

Safari 16.4 added WASM SIMD (official WebKit release note):
https://webkit.org/blog/13966/webkit-features-in-safari-16-4/

That is a feature prerequisite, not a memory guarantee. Official WASM config starts
at 512 MiB and permits growth; model download/crypto/MEMFS copies add pressure.
No reliable universal per-tab iPhone memory limit was established. Historical
WebKit bug reports are device/version-specific and cannot prove this app fails
or succeeds. No iPhone/Android hardware, browser microphone permission flow,
suspension, sustained load, first-download behavior or TTS concurrency was tested.
The prior Windows browser safety stop was respected throughout.
