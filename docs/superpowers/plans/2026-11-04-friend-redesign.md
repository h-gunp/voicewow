# VoiceMate Friend Redesign Implementation Plan

> For agentic workers: independent file ownership, followed by integrated verification and independent Astra review.

**Goal:** Refresh the whole app's visual identity while preserving practice and audio behavior.

**Architecture:** Shared visual tokens implemented in Flutter theme and web CSS. Existing widgets and HTML retain functional hooks. No new runtime dependencies.

**Tech Stack:** Flutter/Dart, semantic HTML, CSS, existing Node tests.

**Spec:** ../specs/2026-11-04-friend-redesign-design.md

## Constraints and review focus

- Preserve audio lifecycle, model consent, navigation, recording locks and script position behavior.
- Keep text readable on glass; solid fallback for essential content.
- Verify narrow/large-text layout, focus and touch targets.
- Remove any obsolete native demo entry per earlier user request without deleting internal audio functionality.
- No merge or deployment; browser/device validation limitations must be disclosed.

## Tasks

- [x] Inspect current UI and baseline Node tests (314 passed).
- [x] Terra shell: app_theme.dart, app.dart, screens/*.dart, widgets/volume_gauge.dart. Preserve controller interfaces.
- [x] Terra features: pronunciation presentation and native prosody screen/chart. Consume shared theme.
- [x] Terra web: prosody index.html/styles.css. Preserve all functional IDs and data hooks.
- [x] Integrate formatting, existing Node/Flutter tests, analyze and release build. Add layout regressions only where meaningful.
- [ ] Independent Astra review of exact final diff; resolve findings and verify changed areas.
- [ ] Commit, push and create draft PR with checks and limitations. Do not merge/deploy.

## Verification so far

Node 314/314; Flutter 241/241 including 320px large-text controls and 200% meter labels; analyze clean; release web build passed. First test run found large-text meter overlap, corrected by reclaiming gauge label width. Astra found short-screen flex collapse risk, corrected with usable deck floors. Browser/device visual verification remains unperformed; previous safety stop is respected.
