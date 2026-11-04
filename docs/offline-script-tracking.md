# Local Korean script tracking implementation

This follows the first native feasibility spike. It connects actual offline
Korean ASR to the existing prosody microphone stream. It remains an explicitly
opt-in experimental feature, with actual mobile/browser validation outstanding.

## Behavior

In own-script practice, enable voice-based script position and press prepare.
Preparing downloads 140,919,603 bytes of fixed public model assets; the vendored
official browser runtime is another 15,351,574 bytes before HTTP compression.
Preparation does not request the microphone. A checkbox and separate button make
the large download intentional. Clear notices say iPhone/Android are unverified.
Once prepared, the existing record action starts recording and a second local
Web Audio graph captures the SAME stream for ASR. No additional getUserMedia call
or remote service is used. Ordinary practice remains available with this off.

The ASR worker recognizes mono PCM at the context's actual rate; sherpa performs
the resampling. The worklet sends 100ms chunks, bounded to four unacknowledged
chunks. The client waits for each ASR result before acknowledging. A slow device,
interrupted graph, missing AudioWorklet or model failure disables tracking with a
message; it never silently skips PCM or fabricates a position. Existing recording
continues independently when tracking alone fails. End-of-record cleanup ends
tracking immediately; no final ASR transcript is saved or shown as a score.

## Source alignment and uncertainty

The selected practice chunk maps sequentially to original UTF-16 source offsets,
preserving decomposed Hangul, punctuation, whitespace and repeated occurrences.
Alignment finds a unique exact block of at least six normalized characters.
Unlike the first suffix-only experiment, a matching earlier block can survive an
ASR substitution at the end. Only that block is highlighted; the UI explicitly
says the later/current position is uncertain. Mismatched characters are never
highlighted and elapsed time never advances a text cursor.

Partial hypotheses must survive a newer audio sequence before display. A changed
or ambiguous hypothesis clears the mark. An endpoint can accept its latest block
directly. These are heuristics, not calibrated recognition confidence or proof of
pronunciation. Multiple-letter token timestamps are not split into character
times. Short phrases may remain unmarked; the current threshold is conservative.

## Privacy and memory ownership

Only five asset GETs are expected during cold worker initialization: local WASM
and four immutable model URLs. Model requests omit credentials and referrer and
include neither script nor PCM. Byte counts and SHA-256 are checked. Downloads
use fixed-size buffers and reject excess bytes. HTTP caching may help later
loads, but eviction/offline reload is not guaranteed. No audio/script cache,
analytics or Web Speech remote fallback is added.

Starting ASR terminates the TTS worker via cancelGuide. Starting new TTS stops
ASR. ASR stops on mode/phrase change, recording end, cancellation, worker failure,
host cleanup, hidden document or page exit. PCM bridge owns its AudioContext but
never stops the shared media tracks. Pending initialization is abortable; stale
callbacks cannot reattach capture. Model MEMFS files are removed after successful
recognizer construction. The WASM heap remains 512MiB until its worker terminates;
do not assume recognizer.free or unlink immediately returns memory to the OS.

## Direct verification

- Alignment fixtures: all four initial public ASR outputs now find a supported
  block, but two retain `uncertain-tail`; this is NOT four fully accurate reads.
- 27 robustness conditions: four public utterances clean/10dB/0dB synthetic white
  noise, repeated audio+script, unrelated script, three bundled TTS clips, one
  additional official Korean sample without a verified transcript, silence,
  synthetic white noise and a tone. The four wrong-script cases and three pure
  nonspeech cases returned no range. The 0dB cases abstained. Repeated full audio
  may identify a unique longer cross-boundary block; identical isolated repeats
  abstain. This small suite does not measure general accuracy or real noise.
- Official browser WASM actually ran under Node MEMFS, then the actual
  asr-worker.js ran in a Node VM with local-file GET shims. Four fixtures emitted
  endpoints without errors; duplicate sequence was rejected. A longer streamed
  silence tail improved some recognition compared with the first EOF harness.
- Current actual-worker run: 1.366s initialization, 816,192KiB process peak RSS.
  VM Response/model copying contributes to this figure. WASM heap is 512MiB.
  Neither number is measured iPhone peak memory or microphone-to-screen latency.
- Mocked UI/worker/Web Audio tests cover opt-in, cancellation, late callbacks,
  hidden-page cleanup, bounded queue, sequence gaps, interrupted contexts and
  decode failure. A hidden-page resource leak was reproduced then fixed.

Reproduce (after `download-model.py` from the spike document):

```
node --test tests/audio/*.test.mjs tools/prosody-web-tests/*.test.mjs
node tools/asr-spike/evaluate.mjs
node tools/asr-spike/measure-application-worker.cjs
```

Results are in `tools/asr-spike/evidence`. Runtime provenance, hashes and collected
notices are described in `docs/wasm-asr-feasibility.md` and vendor/sherpa/README.md.
No public evaluation WAVs/model weights are committed. Converted-model Apache
provenance follows the original card; do not invent a separate converter license.

## Still unverified

Actual browser mic permission/CORS/cache behavior, live latency and long sessions;
iPhone Safari/Android Chrome memory pressure, tab suspension and real TTS↔ASR
transitions; representative Korean speakers, real noise, false-ASR hallucinations,
and 320px/200% layout with the new optional controls. No browser automation was
attempted after the prior Windows safety stop, and no actual-device access is
claimed. The default is off; do not describe this as validated mobile support.
