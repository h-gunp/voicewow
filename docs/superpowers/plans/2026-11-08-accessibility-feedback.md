# Accessibility feedback implementation plan

**Goal:** Make text size discoverable across all three features, explain how to start, and show real prosody loading states with optional preparation guidance.

**Architecture:** Keep the existing Flutter shell and prosody iframe. Reuse SharedPreferences for one saved text-size choice. Add one shared guide screen; no new dependency, model, account, or audio service.

## Scope and design

- Preserve existing design, local-only inference, audio cleanup, comparison colors, and all three features.
- Common text-size control: default / large / larger, composed with system text scaling. Apply to the embedded prosody page too. Loading saved preferences must not block first render or overwrite a newer user choice.
- Common help control plus a first-use entry on the situation screen. Opening help stops current capture/playback while retaining the mounted screen, typed drafts, and completed comparisons. No mandatory onboarding.
- User-paced preparation: comfortable posture, gentle breathing, brief comfortable speech, then choose a feature. Previous/next/skip remain available; no forced timer, breath holding, or neck pressure instructions.
- Feature help describes actual button order, download needs, color meanings, and measurement limits. The order is a navigation suggestion, not a clinically validated treatment protocol.
- Prosody shows startup progress, real module-init readiness, failure and retry; models remain lazy. Font-size messages check origin and iframe source. Disposed or superseded frames cannot change current state.

## Work and verification

- [x] `app.dart`, `app_theme.dart`, text preferences: compose and persist scaling; test delayed load, save failure, navigation cleanup, 320px layout with large text.
- [x] `widgets/training_guide.dart`: shared preparation and help; test step navigation, skip and feature callbacks without microphone access, and 200% layout.
- [x] Prosody iframe and web assets: readiness, retry and scale propagation; test cold startup, no eager models, invalid messages and bootstrap failures.
- [x] Run Flutter tests/analyze, Node audio/prosody/pronunciation/ASR tests, and web release build. Review the complete diff; browser UI verification was unavailable.
- Release procedure: commit, push, package the clean source, deploy to the existing public Site, and verify deployment status. Record the deployment receipt separately from this pre-release source commit.

## Automated verification, 2026-11-08

- Flutter: 341 tests passed; `flutter analyze --no-pub` reported no issues.
- Node: 466 tests passed across audio, prosody, pronunciation, and ASR.
- JavaScript web release build passed. The existing `flutter_tts` Wasm dry-run warnings remain; this is not a Wasm build.
- Layout fixtures cover 320px with 200% text, and pronunciation preparation, recording, comparison, and help round trips at 320x568 with 300% text.
- Help regression tests preserve unsaved sentences, completed comparisons, and prosody guides/results. Cancelled recordings cannot reactivate an invalid replay button.

## Guidance sources

- NHS, general breathing guidance (not hearing-loss therapy evidence): https://www.nhs.uk/mental-health/self-help/guides-tools-and-activities/breathing-exercises-for-stress/
- NIDCD, voice care: https://www.nidcd.nih.gov/health/taking-care-your-voice
- ASHA, voice disorders and clinician-directed manual techniques: https://www.asha.org/practice-portal/clinical-topics/voice-disorders/
- W3C, text resizing: https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html

The feedback and attached screenshots define the requested UX. The linked Daum post could not be fetched; its app behavior is not assumed. Expert consultation and actual iPhone acoustic/performance testing are not completed by this implementation.

## Deliberate limits

- The embedded page scales DOM text and controls; canvas axis labels retain their existing sizes. They need geometry and hit-target changes together, not just a font substitution.
- No diagnosis of the iPhone startup delay is claimed. Code inspection found already-lazy model workers; this change exposes actual readiness/failure and skips drawing hidden graphs.
- Browser automation was unavailable in this session. Automated Flutter layout tests and Node fixtures do not establish real Safari rendering, physical microphone behavior, or clinical effectiveness.
