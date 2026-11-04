# Offline Korean script tracking: feasibility result

2026-11-04. Branch `codex/offline-script-tracking`, base main `f848720`.
This is an isolated, throwaway spike, NOT a shipped feature. No application
imports, audio capture, remote transcription, Web Speech fallback, or UI changes.

## Decision

Local Korean recognition is technically usable in a native Windows process.
Browser/mobile feasibility is NOT established. Do not deploy a tracking UI from
these results. A conservative exact-match baseline deliberately abstained on
two of four public samples because ASR substitutions prevented a reliable match.
Improving coverage without jumping to the wrong repeated phrase needs more work.

The approved direction is local streaming ASR plus source alignment. Remote ASR
is excluded by privacy requirements; elapsed-time highlighting cannot establish
what was spoken. Native inference is used here only to separate model behavior
from browser memory/platform constraints. It is not a substitute for WASM tests.

## Reproduce

From repository root (Node 24 and Python 3):

```
npm ci --prefix tools/asr-spike --ignore-scripts
python tools/asr-spike/download-model.py
node --test tools/asr-spike/alignment.test.mjs
node tools/asr-spike/measure.mjs
```

The downloader gets fixed public assets from a pinned upstream revision. Models
and WAVs stay under ignored `.local/asr-spike`, not in Git or the Site. Inference
reads those files locally; it has no HTTP code. Checked-in evidence is only the
upstream public sample output, hardware metadata and measurements.

## Measured on this desktop

Windows x64, Intel i5-13400F, Node 24.16.0, `sherpa-onnx-node` 2.0.1
(runtime revision `af2d8d81`), CPU execution, one thread, greedy decoding.
Public fixtures are short (2.68–6.63 seconds), not a representative evaluation.

| Metric | Observed |
| --- | --- |
| Four required model files | 140,919,603 bytes (134.39 MiB) |
| First model download, desktop connection | 8.105 seconds, excluding runtime and metadata |
| Recognizer initialization | 1.407 seconds |
| Process maximum resident set | 271,528 KiB (265.16 MiB) |
| Processing / audio duration | 0.055–0.059 (native, unpaced file input) |
| 160ms input chunk, p95 compute | 17.1–17.9ms |
| Input consumed before first nonempty hypothesis | 0.80–1.12s |
| Exact final-suffix alignment | 2 / 4 samples; other two abstain |

These are single-run observations, not guaranteed performance. RSS includes the
process and is not WASM heap size. First-hypothesis input time is NOT measured
microphone-to-screen latency. EOF is supplied by this harness; upstream returned
`is_final:false` even after inputFinished. No live endpoint/stability policy has
been validated. Token timestamps often describe multi-character pieces; they
must not be divided into invented per-character pronunciation timestamps.

## Alignment contract tested

The baseline accepts finalized hypotheses explicitly. Partial revisions return
no range. It normalizes Unicode graphemes while retaining original UTF-16 source
offsets (including decomposed Hangul, emoji, spaces and punctuation). It requires
at least six normalized matching characters and a unique suffix. It shows only
the matched span, not skipped text, and returns preceding/following source text.
It can move backward for rereading. Repeated phrases abstain unless an explicit
selected source range disambiguates them. No distance-based automatic jump, fuzzy
probability, pronunciation score, or character timing is asserted.

Ten synthetic contract tests pass. They do not establish ASR accuracy. A unique
text match can still be an ASR hallucination; product language must say an
estimated ASR-matched range, with uncertainty and manual recovery. Consecutive
streaming hypothesis stability, bounded source windows and robust edit alignment
are future experiments, not implemented capabilities here.

## Browser, memory and lifecycle gate

Official [WASM ASR build configuration](https://github.com/k2-fsa/sherpa-onnx/blob/master/wasm/asr/CMakeLists.txt)
currently requests 512MB initial memory and allows growth, with model preloading.
That is not a peak memory bound. JS download buffers, filesystem/model copies,
inference state, Flutter and other workers may add memory. Emscripten, Android
device tooling and physical iPhone access were not available in this environment.
The previous Windows Chrome safety stop was respected; no alternate browser
automation was attempted. No WASM/browser/device benchmark was run.

Existing Supertonic TTS uses approximately 400MB of model downloads and retains
its worker after completion. `cancelGuide()` terminates it. Any future ASR start
must terminate TTS first, await in-flight cancellation, retain only needed guide
PCM, and avoid overlapping ASR/TTS downloads. Before generating another guide,
terminate ASR; on tab exit/stop/error terminate the worker, cancel downloads and
discard stream buffers. Worker termination/reclamation still needs device
measurement. This spike does not modify or claim to test that integration.

Required next evidence: pinned WASM build, cold/warm/offline reload, download
cancellation and cache eviction, sustained microphone decoding and UI latency,
TTS→ASR→TTS transitions, memory pressure/tab suspension on actual iPhone Safari
and Android Chrome, and representative Korean repetitions/omissions/corrections.
No simulator or desktop-native number can close the actual-device gate.

## Provenance, licenses and privacy

- [Official Korean model documentation](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html)
  identifies the Korean streaming Zipformer model.
- [Converted model repository](https://huggingface.co/k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16/tree/ba6078bca4daf3f0dd37f79d0ab505af71df14a6)
  is pinned to `ba6078bca4daf3f0dd37f79d0ab505af71df14a6`. Three model binary SHA-256
  digests are checked against upstream LFS metadata; sizes are checked for every
  downloaded file. Token/sample digests are recorded for reproducibility.
- [Original model card](https://huggingface.co/johnBamma/icefall-asr-ksponspeech-pruned-transducer-stateless7-streaming-2024-06-12)
  declares Apache-2.0. The conversion card links to it but contains no independent
  license declaration. This is provenance evidence, not independent clearance of
  every dataset/sample. Do not redistribute weights or samples in this PR. Confirm
  converted-weight notices and sample rights before public bundling.
- [Sherpa runtime license](https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE)
  is Apache-2.0. Distribution must retain the applicable license/notices and mark
  modifications; future WASM packaging must audit bundled ONNX Runtime and other
  dependency notices. This PR pins a development dependency only.
- Downloads disclose ordinary connection metadata to the public model host, but
  contain no user script/audio. Neither script nor PCM is sent to a server. No
  remote fallback, telemetry or user recording persistence is introduced.

Evidence: `tools/asr-spike/evidence/*.json`. An independent Astra review should
review these claims and experiment code; passing review does not establish
iPhone support or authorize presenting the spike as a completed feature.
