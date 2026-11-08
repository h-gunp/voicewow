# Direct prosody surface

The user requested removal of the iframe after the startup deadlock investigation. Render the existing prosody UI directly in the app document using a div with an isolated ShadowRoot. Preserve the current HTML/JS audio features and Flutter navigation; switching to the native prosody implementation would remove web-only guide generation and tracking features.

## Contract and scope

- Flutter creates a div with HtmlElementView and calls `voiceMateProsody.createSurface(host, onExit)`. The returned handle has `ready`, `pause()`, `dispose()`, and `setTextScale(number)`.
- The app bootstrap registers this small bridge before starting Flutter. Creating the surface lazily loads its HTML/CSS and app module; no model, microphone, or playback is started on entry.
- `createProsodyApp({document, window, embedded, onExit, baseUrl})` owns per-mount state and returns pause/dispose/resize. Queries stay inside the surface. Global listeners, timers, workers, object URLs, and pending microphone requests are released on dispose.
- Preserve drafts and completed results while help is open by pausing without disposing. Leaving the feature disposes the surface. Late work from an old surface must not mutate or stop a newer surface.
- Scope styles and local scrolling; replace rem's document-root dependency with a surface text unit and viewport-height assumptions with the measured surface height. Resolve audio and link paths against the module/template URL.
- Remove iframe navigation, postMessage readiness/cleanup, and the obsolete iframe URI/source-validation contract. Keep loading/error/retry and paint coverage for the direct platform view.

## Checks

Run the existing prosody Node behavior suite against the factory; add mount/dispose/remount, scope isolation, relative assets, scale, resize, and no-eager-audio checks. Run Flutter tests/analyze and the web release build. Review changed callers and publish the clean pushed source to the existing public Site.

Browser automation was blocked by URL verification in this session. Fixture and render tests do not establish real Safari audio behavior.

## Verified implementation

- Flutter 336 tests passed, static analysis reported no issues, and the JavaScript web release build passed.
- Node 477 tests passed across audio, prosody, pronunciation, and ASR. The obsolete iframe transport tests were removed; direct mount lifecycle, CSS readiness, module reuse, instance isolation, partial-init cleanup, and asset URL checks replace that transport contract.
- The pre-existing flutter_tts Wasm dry-run warnings remain; the release targets JavaScript.
- No iframe element or iframe message protocol remains in the app-owned prosody presentation code. Audio workers still use their normal worker messaging.
- Actual browser text input/focus, font rendering, and device microphone behavior remain unverified. The Computer Use tool blocked Chrome interaction because it could not validate the current URL.
