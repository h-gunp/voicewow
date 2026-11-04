# VoiceMate quality fixes: validation and open limits

Baseline: `fdad24e80283b2e363b5a751d3c22f0fe692d8fc` (PR #24).

## Included behavior

- Speech display now requires libfvad and adjacent RNNoise speech scores to agree. The gauge continues to hide unclassified input, including when processing is disabled or unavailable.
- A newly visible speech gauge starts at the measured value, avoiding a new 150 ms animation from zero on every syllable. Subsequent live level changes still interpolate. Gain, the +114 display offset, and scenario reference ranges are unchanged.
- Ambient adaptation uses one second of eligible non-speech in a three-second window and two seconds of sustained candidate evidence. It responds to smaller changes and caps large changes at the existing +3 limit. Zero-valued input alone does not establish a baseline.
- Prosody opens with a prepared-example / own-script choice. Script editing, guide preparation, and preview have separate preparation views. Returning to the same mode preserves accepted recordings/results. Busy operations keep navigation locked while recording Stop remains available.
- The demo link and embedded volume-return button are removed. Flutter's bottom navigation and frame/audio cleanup contract remain intact.
- Script practice shows the selected unit and preceding/following units, with manual navigation. It does not claim to recognize the character currently being spoken.

## Evidence and limitations

The original gauge implementation fails the first-frame height regression with a zero fill; the corrected implementation passes. Stored guide recordings at normal and -20 dB gain retain 70–85% of the previous VAD-positive frames. This small fixture set is not a general speech-quality benchmark. No real dog-bark/clap corpus or live microphone test was performed, and perfect human-only classification is not established.

Synthetic ambient tests cover four-second speech / two-second pause cycles, small and capped sustained rises, zero-input recovery, speech/uncertain/clipped input exclusion, and short transients. A +4.77 dB sustained rise reaches +1 around 4.7 seconds and +2 around 6.8 seconds in the test conditions, compared with 14/19 seconds before. These are simulated input-power results, not device sound-pressure measurements.

Widget/DOM tests cover preparation guards, same-mode result preservation, recording locks, and Stop availability. Source structure keeps Stop outside the recording content's scroll area. Actual web layout at 320×568, 200% text/zoom, real iPhone microphone behavior, and model download remain unverified.

## Independent-review corrections

The review of head `193cf1e` reproduced two defects that the original suites missed. Both have dedicated failing-before/passing-after regressions:

- A positive libfvad result with low RNNoise scores incorrectly became `nonSpeech`. It now remains `uncertain`, so neither absolute nor relative ambient estimators may learn from this disagreement. The integration regression uses real RNNoise with seeded synthetic input and a controlled VAD decision; a negative-VAD control still calibrates agreed background. Stored speech fixtures additionally assert that rejected VAD positives never become background. The six retained-frame counts are unchanged: hello 85/101 and 84/99, phrase 132/167 and 136/161, sunglasses 70/100 and 65/82 (normal / -20 dB gain).
- Selecting the initial prepared-example mode left charts drawn at the hidden 500px fallback width. Same-mode entry now redraws after revealing the workflow, preserving the selected guide, recording and comparison. The regression models `clientWidth` changing from 0 while hidden to 253 when visible and checks a 506×510 bitmap, including returning to a saved result after a hidden resize. This is a layout-aware DOM simulation, not a replacement for the reviewer's actual-browser recheck.

The reviewer observed the original-head UI in a separate in-app browser at 320×568, including the original chart defect. That observation does not resolve the earlier Windows Chrome blank-frame symptom. Browser control was not resumed for these corrections.

## Open iframe investigation

No iframe implementation change is included. The blank-frame symptom remains unresolved.

Read-only HTTP checks returned the practice HTML successfully, and direct practice-page navigation worked. Some local ordinary-iframe and top-level Flutter controls rendered, while other embedded/viewport/redirect comparisons showed blank frames. These inconsistent observations do not establish a reliable source-level root cause. Waiting for attachment, adding a container, and using the canonical directory URL did not produce a verified fix and were excluded.

Native browser verification was stopped because the computer-use tool could not determine the current Windows browser URL confidently enough to enforce policy. No alternate control path was used after that stop. The diagnostic worktree and generated experiments are not part of this PR or its release build.

## Automated checks

Run from the repository root:

```text
node --test tests/audio/*.test.mjs tools/prosody-web-tests/*.test.mjs
```

Run from `apps/client`:

```text
flutter test
flutter analyze
flutter build web --release
```

An independent Astra review and resolution of the open release checks are required before merge/deployment.
