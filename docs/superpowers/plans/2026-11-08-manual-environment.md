# Manual Environment Sampling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 환경음 버튼으로 수집한 참고 기준선을 고정하고 기존 소음억제·발화 표시를 유지한다.

**Architecture:** 하나의 캡처 연결에서 수동 환경 수집 상태와 발화 표시를 분리한다. 현재 JS 분석 이벤트를 확장하고 Flutter 화면·컨트롤러가 수집과 재측정 상태를 표시한다.

**Tech Stack:** Flutter/Dart, AudioWorklet, RNNoise/libfvad, Node test다.

**Spec:** [승인된 수동 수집 설계](../specs/2026-11-08-manual-environment-design.md)를 따른다.

## Global Constraints

- 기존 디자인·음량·높낮이·발음 기능을 보존한다.
- 음성 업로드·외부 분석·새 패키지는 추가하지 않는다.
- 이동량 0..3과 초기 수집 통계는 실험적 참고값으로 표시한다.
- 현재 깨끗한 `codex/enrollment-first` 체크아웃에서 파일 소유권을 나눠 작업하며 같은 브랜치로 푸시한다. 사용자가 실행·검토·푸시·배포를 승인했으므로 추가 승인 대기는 하지 않는다.

## Review Focus

- 배경 대화와 uncertain 판정이 있어도 유효한 환경 입력을 수집해야 한다.
- 취소·재측정 실패는 이전 성공 기준을 보존하되 입력 변경은 폐기해야 한다.
- 긴 발화와 비발화가 기준선 이동 또는 5초 만료를 일으키지 않아야 한다.
- 중지·새 시작·설정 변경·늦은 이벤트가 완료 결과를 되살리지 않아야 한다.
- 작은 화면·큰 글자에서도 수집/취소 버튼과 안내를 사용할 수 있어야 한다.

### Task 1: JS 수집과 캡처 연결

**Files:** `web/audio/environment-estimator.mjs`, `capture-bridge.mjs`, 관련 `tests/audio`를 수정한다.
**Interfaces:** createCapture의 `sampleEnvironment()`/`cancelEnvironment()`와 spec의 analysis 필드를 제공한다.

- [x] 새 수동 수집·초기 시끄러운 환경·고정 유지·취소·불안정·디지털 무음·클리핑·중복/공백 프레임 검사를 작성하고 실패를 확인한다.
- [x] spec의 500/400프레임, 10%클리핑, 12dB IQR, -60/10/3 보정 규칙을 구현한다.
- [x] 캡처의 fresh/epoch/settings 검증을 유지하며 자동 환경 학습을 제거한다. 기존 RNNoise/VAD 미터 계산은 보존한다.
- [x] 관련 Node 검사를 실행하고 독립 검토를 받는다.

### Task 2: Flutter 제어와 화면

**Files:** `audio_port.dart`, `web_audio_port.dart`, `unsupported_audio_port.dart`, `session_controller.dart`, `meter_screen.dart`, 모든 관련 FakeAudioPort와 Flutter 검사를 수정한다.
**Interfaces:** AudioPort의 위 두 async 메서드를 JS로 전달하고 SessionController가 수집 가능/수집 중 상태와 이벤트를 관리한다.

- [x] 버튼·진행 상태·기준 고정·재측정 실패·이탈·late-event·모바일 레이아웃 검사를 작성하고 실패를 확인한다.
- [x] 수집/취소와 실험적 참고 안내를 기존 화면에 추가한다. 입력을 끊지 않고 수집 상태를 전환한다.
- [x] 새 이벤트 유효성에 따라 기준선을 적용하고 수집 중 발화 막대를 비운다.
- [x] 관련 Flutter 검사를 실행하고 독립 검토를 받는다.

### Task 3: 통합 검토와 게시

- [x] 문서를 현재 수동 수집 동작에 맞추고 전역 불변 조건·합성/실기기 경계를 기록한다.
- [x] 전체 Node/Flutter 검사, analyze, release build, diff 검사를 실행한다.
- [x] 독립 최종 검토에서 확인된 문제를 수정하고 영향받는 검사를 재실행한다.
- [ ] 실제 코드 커밋·원격 HEAD를 확인한 뒤 Sites 소스 helper로 기존 공개 사이트에 게시한다. 발음 모델은 기존 GitHub 고정 커밋에서 다운로드하며 배포 아카이브에 포함하지 않는다.
- [ ] 배포 결과와 가능한 공개 자산 검증을 보고하고 실기기 미검증 사항을 구분한다.
