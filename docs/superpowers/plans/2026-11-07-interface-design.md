# VoiceMate Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 등록·상황 선택·측정·진단 화면을 같은 시각 체계로 정리한다.

**Architecture:** 기존 StatelessWidget과 SessionController 연결을 재사용한다. 공통 테마와 외곽 레이아웃, 화면별 시각적 위계만 바꾸며 새 의존성은 추가하지 않는다.

**Tech Stack:** Flutter, Dart, 기존 Flutter widget tests다.

**Spec:** `docs/superpowers/specs/2026-11-07-interface-design.md`다.

## Global Constraints

- SessionController, 오디오 포트, 워커, 보정값, 참고 범위, RNNoise와 화자 판별 동작은 변경하지 않는다.
- 새 의존성, 새 로고·이미지, 가짜 파형·측정값·정확도 수치는 추가하지 않는다.
- 공개 저장소 push나 배포는 이 작업에 포함하지 않는다.
- 0–120 수직 좌표, 빨간 상·하한, 글자 200% 확대와 모델 고지 접근을 유지한다.

## Review Focus

- 320px 화면에서 글자 200%를 적용해도 조작과 기준선 라벨이 겹치지 않아야 한다.
- 넓은 화면은 기존 460px 외곽 프레임에 갇히지 않아야 한다.
- 측정 중지 조작이 보조 화자 등록과 긴 분석 설명보다 앞에 있어야 한다.
- 수집 진행 표시는 실제 samples와 등록 완료 latch만 반영해야 한다.
- 비발화·오류·중지 상태에는 게이지 채움이 없어야 한다.

### Task 1: 공통 화면과 등록·선택 화면

**Files:** `app_theme.dart`, `app.dart`, `screens/enrollment_screen.dart`, `screens/scenario_screen.dart`, `web/index.html`, `test/interface_layout_test.dart`다.

**Interfaces:** 기존 screen 생성자·Key·callbacks와 테마 상수 ink/muted/line/canvas/red를 유지한다. 포인트색은 accent로 명명한다.

- [x] 넓은 화면의 선택 행 폭과 작은 화면의 등록·선택·진단 접근을 검증하는 테스트를 먼저 작성하고 기존 구현의 실패를 확인한다.
- [x] 먹색·밝은 중립 배경·짙은 녹색 포인트로 테마를 바꾸고 외곽 프레임을 없앤다. 제목 체계를 통일하고 선택 카드를 행으로 바꾼다.
- [x] 등록 설명·수집 개수·상태·주 동작을 나눈다. 기존 취소·재시도·skip 로직과 모델 안내를 유지한다.
- [x] 새 테스트와 기존 등록 테스트를 실행한다.

### Task 2: 측정과 진단 화면

**Files:** `screens/meter_screen.dart`, `widgets/volume_gauge.dart`, `test/interface_layout_test.dart`다.

**Interfaces:** 기존 VolumeGauge 생성자와 마커·채움 Key를 유지한다. 입력값·상태 문구와 callbacks를 유지한다.

- [x] 중지 조작이 화자 등록보다 앞에 있는지 검사하는 테스트를 먼저 작성하고 실패를 확인한다.
- [x] 게이지의 좌표식을 유지하며 눈금·단색 채움으로 바꾸고 측정값과 조작을 앞쪽에 둔다. 화자와 환경 분석은 구분선으로 나눈다.
- [x] 진단은 왼쪽 정렬과 섹션 제목으로 나누고 기존 값을 보존한다.
- [x] Flutter 전체 테스트, analyze와 release 웹 빌드를 실행한다. Node 오디오 코드는 변경하지 않으므로 재검사 범위를 늘리지 않는다.
- [x] Flutter 렌더링으로 모바일·데스크톱 화면을 확인하고 독립 리뷰를 받는다. 실제 브라우저·마이크 검증과 구분해 보고한다.

## 실행 결정

사용자가 세부 판단을 맡겼으므로 추가 실행 방식 선택은 요청하지 않는다. 현재 전용 기능 브랜치 `codex/enrollment-first`에서 작업하며 사용자 요청 없이 브랜치 이동·커밋·공개 전송은 수행하지 않는다. 이전 턴에서 Flutter 66개 테스트가 통과했다.
