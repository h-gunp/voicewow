# Environment adaptation implementation plan

> **For agentic workers:** Use superpowers:executing-plans task by task. Independent review is coordinated by the parent chat after local verification.

**Goal:** 기존 상황 선택을 유지하면서 원본 에너지 기반 잡음·발화 추정과 지속 환경 변화 추적을 구현한다.

**Architecture:** 단일 RNNoise worklet에서 원본 10ms 에너지와 처리 후 VAD를 동기화한다. bridge는 표본/수신 시각과 세션 조건을 검증하고 Dart의 단일 추정기가 통계와 목표를 계산한다. 기존 게이지와 별도 참고 영역을 구분한다.

**Tech Stack:** Flutter 3.47.7, Dart, native JavaScript AudioWorklet, bundled RNNoise, pinned libfvad WASM.

**Spec:** 이 채팅의 승인된 설계와 `docs/environment-adaptation.md`다.

## Global Constraints
- +114는 사용자가 실험에서 웹사이트 측정값과 앱의 보정 전 값 사이 차이를 직접 관측해 얻은 보정값이다.
- 절대 SPL 교정·전 장치 유효성·초기 소음 자동 분류·화자 식별을 주장하지 않는다.
- 모든 새 임계값은 미검증 실험값이다. 마이크 권한·실제 녹음·원격 작업·배포는 하지 않는다.
- 사용자 변경을 보존하고 현재 체크아웃의 로컬 브랜치에서 수행한다. 부모가 독립 리뷰한다.

## Review Focus
- 묵은 이벤트와 중복 표본으로 목표가 움직이지 않아야 한다.
- 작은 타인 발화가 RNNoise로 지워질 때 불확실 구간을 잡음으로 승인하지 않아야 한다.
- 설정 변경/누락과 장치 재시작은 이전 기준을 재사용하지 않아야 한다.
- 음수 차감·무음·낮은 SNR·stale은 유효 발화값을 만들지 않아야 한다.
- 보정 상한을 초과하면 최대 발성을 권하는 대신 지원 불가로 전환해야 한다.

### Task 1: 별도 VAD와 원본 프레임
Files: `web/audio/voice-activity.mjs`, `noise-reducer.mjs`, `noise-reduction-worklet.mjs`, `noise-reduction.mjs`, vendor/libfvad, `tests/audio/voice-activity.test.mjs`, 기존 reducer/worklet/loader tests다.
Interface: `createVoiceActivity(wasmBinary)` returns process(Float32Array480), dispose(). `createNoiseMeter` preserves levels and adds aligned analysis blocks when VAD is available.
- [ ] 고정 배포물 해시·LICENSE·PATENTS·소스 추적을 확인한다.
- [ ] 실제 WASM 프레임, 비유한 값, 해제, 원본 에너지/표본 정렬 실패 테스트를 먼저 실행한다.
- [ ] VAD 및 RNNoise 경로를 구현하고 Node suite를 통과시킨다.

### Task 2: 증거 기반 추정기와 이벤트
Files: `lib/audio/environment_estimator.dart`, `audio_port.dart`, `web_audio_port.dart`, `capture-bridge.mjs`, matching tests다.
Interface: AnalysisFrame with seq/sampleStart/sampleEnd/sampleRate/sampleTime/receivedAt and ten 10ms raw power/VAD blocks; EnvironmentEstimator.add(frame, supported), reset(), expire(sampleTime). Identity envelope sessionId/deviceEpoch/settingsRevision.
- [ ] 초기 적격 3초·200/500ms 경계·10초 창·stale 5초·중복·순번 누락·보정 상한·에너지 차감 실패 테스트를 실행한다.
- [ ] 원본 에너지 중앙값/IQR와 evidence-time EMA를 구현한다.
- [ ] 지속변화 3/1.5dB hysteresis, fresh evidence 3초/elapsed5초/gap2초, change step1/cap3을 구현한다.
- [ ] bridge와 Dart 경계 검증, 설정 초기화, 전처리 false 조건을 적용한다.

### Task 3: 세션/화면 및 검증
Files: SessionController, MeterScreen, tests/fakes, README, THIRD_PARTY_NOTICES and design doc다.
- [ ] 토글 OFF/설정 변경/stop/start/stale/불확실 UI 테스트를 먼저 실행한다.
- [ ] 기존 입력 게이지·상황 선택을 유지하고 새 추정값·보류 사유를 별도로 표시한다.
- [ ] Node 전체 tests, Flutter test, analyze, release web build를 실행한다.
- [ ] 실제 실행 결과와 제한을 기록하고 독립 리뷰를 위해 중지한다. 로컬 diff로 인계하며 자동 커밋하지 않는다.
