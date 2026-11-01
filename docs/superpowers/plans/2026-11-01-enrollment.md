# Initial enrollment Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** 초기 등록을 안내하고 측정 화면을 간소화한다.

**Architecture:** SessionController가 측정 상황과 독립적으로 마이크를 시작하고 등록 상태를 관리한다. 전용 화면과 앱 라우팅은 기존 AudioPort를 사용한다. 모델 및 진단은 기존 정보를 보존한다.

**Tech Stack:** Flutter, Dart, browser audio JavaScript.

**Spec:** docs/superpowers/specs/2026-11-01-enrollment.md

## Global Constraints

실제 마이크·외부 전송 금지. 기존 모델, 고지, 상대 막대 및 환경 안전 조건을 보존한다. 원격 반영 금지.

- [x] 등록·건너뛰기·재시도·연속 클릭에 대한 동작 테스트를 먼저 작성하고 실패 확인.
- [x] 컨트롤러, 브리지, 전용 화면과 라우팅을 수정하고 테스트 통과.
- [x] 측정 화면 정보와 고지를 접근 가능한 별도 화면으로 옮기고 기존 동작 검증.
- [x] 실제 모델 합성 fixture, 전체 테스트, 모바일 화면을 검증하고 결과와 한계를 기록.

검증 도구는 `C:\Users\hjshg\Desktop\voicemate\.tools\flutter\bin\flutter.bat`, `PUB_CACHE=C:\Users\hjshg\AppData\Local\Pub\Cache`를 사용한다. Flutter 테스트 66개와 오디오 테스트 199개 및 정적 분석을 통과했다. Chrome 로컬 합성 fixture에서 3개 구간 등록, 완료 상태 대기, 계속 버튼과 모드 선택을 확인했다. 별도 워커 진단에서 등록 후 유사·불일치·불확실 결과가 발생했으며 일부 결과는 시간이 지나 확인 대기로 전환됐다. 390×844 초기 화면과 모드 선택 화면을 시각 확인했다. 실제 장치의 마이크 음향 성능과 공개 사이트 전송 상태는 검증하지 않았다.
