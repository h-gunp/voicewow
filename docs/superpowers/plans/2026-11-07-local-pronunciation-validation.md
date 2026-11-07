# Local Pronunciation Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 승인된 화면 교체에 앞서 한국어 음소 모델의 로컬 실행과 실제 녹음 검증 경로를 만든다.

**Architecture:** 기존 vendored ONNX Runtime WASM과 공개 고정 모델을 사용한다. 제품의 발음·높낮이 코드는 건드리지 않고, 개발 검증 페이지에서 파일 또는 명시적 마이크 입력을 로컬 분석한다. 음소·추정 한글·실측 시간을 보여 주고, 실제 발음 검증이 끝나지 않은 결과에는 정오 색상을 부여하지 않는다.

**Tech Stack:** JavaScript ES modules, ONNX Runtime WASM, Node test runner, Python 표준 라이브러리 다운로드 도구, 기존 정적 서버다.

**Spec:** `docs/superpowers/specs/2026-11-07-local-pronunciation-check-design.md`다.

## Global Constraints

- 음성·선택 문장·분석 결과는 외부로 전송하지 않는다.
- 모델 revision은 `dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70`, 가중치는 356,129,122바이트다. 해시·설정·라이선스 출처를 기록한다.
- 모델과 원시 입력은 `.local/`에 두고 git에 넣지 않는다. 새 런타임 패키지는 기존 ORT로 실행할 수 없다는 근거가 생기기 전까지 추가하지 않는다.
- 16kHz mono, 최대 20초다. 마이크는 사용자 버튼으로만 시작하고 이탈·취소 시 정리한다.
- 단위 테스트·합성 음성·Node에서 WASM 실행은 실제 브라우저/기기 발음 정확도 검증과 구별한다.
- 기존 제품 화면은 모델 적합성 검증 전에 교체하지 않는다. 실제 정상/오류 발화 표본이 없으면 그 단계는 미완료로 명시한다.
- 사용자 승인에 따라 추가 실행 방식 확인 없이 현재 작업 브랜치에서 진행한다. 기존 다른 worktree와 저장 데이터를 건드리지 않는다.

## Review Focus

- 무음 정규화가 NaN 또는 확신에 찬 가짜 음소를 만들지 않아야 한다: Task 2에서 검사한다.
- 반복 음소 사이의 blank가 음소를 삭제하지 않아야 한다: Task 2에서 검사한다.
- 권한 대기 중 취소 뒤 늦게 열린 마이크가 남지 않아야 한다: Task 3에서 검사한다.
- 마지막 오디오 프레임을 수신하기 전 분석이 시작되면 안 된다: Task 3에서 검사한다.
- 가중치 크기·해시 오류, 저장 공간 오류, 워커 오류가 기존 앱을 망가뜨리거나 외부 fallback을 만들지 않아야 한다: Task 1·3에서 검사한다.

### Task 1: 고정 모델과 실행 가능성 확인

**Files:** `tools/pronunciation-spike/download-model.py`, `tools/pronunciation-spike/measure.mjs`, `.local/pronunciation-spike/`다.

**Interfaces:** 다운로드 도구는 고정 manifest와 모델·config·vocab·전처리·라이선스를 저장한다. 측정 도구는 Task 2의 `createPhoneEngine({loadAsset})`를 사용하고 JSON 보고서를 `.local/pronunciation-spike/`에 저장한다.

- [x] 다운로드 경로가 `.local/pronunciation-spike` 안에 있고, HTTP 오류·크기·SHA-256 불일치면 성공 파일로 남기지 않는 self-check를 둔다.
- [x] 고정 revision의 공개 파일 메타데이터를 읽고 필요한 파일만 다운로드한다. 음성은 전송하지 않는다.
- [x] 기존 ORT에서 실제 모델을 로드하고 input/output shape를 확인한다. 출처가 확인된 공개 WAV를 로컬로 추론하고 runtime·CPU·초기화·추론 시간·메모리·음소를 보고한다.
- [x] 모델 로드와 추론은 Node WASM에서 성공했다. 실제 발음 평가 적합성은 별도 조건이다.

### Task 2: 모델 전처리·CTC·한글 표기

**Files:** `tools/pronunciation-spike/phone-engine.mjs`, `tools/pronunciation-spike/phones.mjs`, `tools/pronunciation-spike/phones.test.mjs`다.

**Interfaces:** `prepareSamples(samples, sampleRate)`는 유한한 16kHz Float32Array를 반환한다. `decodePhones(logits, dims, vocab)`는 `{phone,startFrame,endFrame}` 목록을 반환한다. `phonesToHangul(phones)`는 추정 표기와 모호한 음소 구간을 반환한다. `createPhoneEngine({loadAsset})`는 `recognize(samples,sampleRate)`와 `dispose()`를 가진다. 원문을 인식기에 전달하지 않는다.

- [x] 무음·NaN·과장 길이 거부, blank와 반복음 보존, unknown 토큰 처리, 정상 초성/받침/된소리, 불완전한 자모를 임의 보정하지 않음 테스트를 먼저 쓰고 실패를 확인한다.
- [x] 원저자 phoneset을 확인해 명확한 자모 매핑만 구현한다. 음절 경계가 모호하면 표시와 반환값에 남긴다.
- [x] 기존 ORT WASM을 가져와 실제 input metadata에 맞는 tensor를 넣는다. decode 후 tensor/session을 정리한다.
- [x] `node --test tools/pronunciation-spike/phones.test.mjs`가 통과하는지 확인한다. 합성 로짓 테스트는 음향 정확도 수치로 쓰지 않는다.

### Task 3: 사용자 검증을 위한 로컬 녹음 페이지

**Files:** `tools/pronunciation-spike/index.html`, `tools/pronunciation-spike/app.mjs`, `tools/pronunciation-spike/worker.mjs`, 필요한 녹음 모듈과 테스트다.

**Interfaces:** Worker 요청 `{type:'prepare'|'recognize', id, samples?, sampleRate?}`, 응답 `{type:'ready'|'result'|'error',id,...}`다. 페이지는 준비→녹음→분석→결과 상태와 취소용 generation을 관리한다. 준비 시 `.local` 모델만 읽으며 외부 요청을 만들지 않는다.

- [x] 준비 실패·중복 입력·취소 후 늦은 결과·권한 대기 취소·20초 제한·끝 프레임 정리를 테스트한다.
- [x] 모델 준비, 명시적 마이크 시작/종료, WAV 파일 입력, 로컬 재생, 음소·추정 한글·소요시간을 구현한다. 검증 전 결과는 중립색이며 '정확도 미검증'을 표시한다.
- [x] 현재 초록·중립색과 유동 폭, 키보드 포커스를 코드에 반영했다. 참고 원문은 모델 입력에 넣지 않는다. 실제 렌더링과 확대 검증은 남아 있다.
- [ ] 기존 서버와 충돌하지 않는 loopback 전용 경로로 제공하고 HTTP 파일 접근을 확인한다. 실제 브라우저 입력 검증은 별도로 기록한다.

### Task 4: 적합성 판정과 다음 단계

- [x] 출처가 확인된 공개 WAV와 무음·잡음을 실행했다. 실제 오발음 표본은 없으며 참고 원문과 음성의 정오 라벨을 구별했다.
- [x] `께/떼`, `써/떠`, 허용 변이, 누락·추가에 대한 근거가 부족해 제품 교체를 보류했다. 잡음에서 음소가 출력되는 사례도 확인했다. 녹음 검증 페이지를 구현했으나 지속 서버 실행은 승인 검토에서 거절됐다.
- [ ] 검증 통과 시 후속 제품 구현 계획을 이어서 작성·실행한다. 해당 계획은 Flutter 목록·상세·개인문장·복습·기능전환, 판정 보류와 허용발음 정렬, Android 추론, 저장 호환 검증까지 포함한다. 이미 승인한 설계 범위에서 다시 허락을 요구하지 않는다.
- [x] 새 단위 검사·기존 Node 회귀 검사를 실행하고 독립 리뷰를 받았다. 제품 코드는 변경하지 않아 Flutter 전체 빌드는 반복하지 않았다.

## 진행 기록

2026-11-07: 설계 승인에 따라 시작했다. 현재 브랜치의 제품 코드는 `530895d`이며 기존 다른 worktree는 수정하지 않는다. 이 계획은 설계의 선행 검증을 구체화한 것으로 최종 기능 전체가 완료됐다는 뜻이 아니다.

Task 1·2 완료다. Task 3의 구현과 모의 수명 검사는 완료했으나 실제 브라우저 렌더링·마이크 검증은 미완료다. 임시 서버 단위 검사 10개는 성공했고, 별도 백그라운드 서버 시작은 자동 승인 검토에서 `blocked by policy`로 거절됐다. 같은 작업을 다른 명령으로 우회하지 않았다.

Ruling: 기존 작업 브랜치에서 실행한다. 사용자에게 다시 실행 방식 승인을 요구하지 않고 모델 탐색·녹음 수명·서버 검사를 독립적으로 병렬 수행했다. 다른 worktree는 변경하지 않았다.

Ruling: `prepareSamples`는 16kHz만 받는다. 브라우저 파일·녹음 변환은 표준 OfflineAudioContext에 맡기며, 모델의 실제 입력에는 attention mask가 없다는 실행 결과를 따른다.

Ruling: 기존 Yuna WAV는 합성이고 현재 checkout에 이전 ASR WAV가 없었다. 기존 다운로드 도구에 정의된 고정 공개 한국어 ASR WAV 두 개를 별도로 내려받고 출처·해시를 기록했다. 이 원문을 음소 정답으로 사용하지 않는다.

Ruling: 모델에서 잡음 5초 → `아`가 나왔다. 한글 표기의 `uncertain=false`는 음향 신뢰도가 아니다. 이 결과와 실제 오발음 자료 부재 때문에 제품 자동 채점·화면 교체를 진행하지 않는다. 후속 제품 단계의 승인 요청을 반복하는 것이 아니라 승인된 검증 조건을 적용한 결과다.

독립 리뷰에서 Critical/Important는 없었다. WAV 재시도 시 완료된 recorder의 PCM 참조가 남는 Minor 한 건은 명시한 녹음 수명 약속에 해당하므로 수정했다. WAV 읽기 전에 recorder.cancel을 기다리고 generation을 재확인한다. 최종 검사는 별도 로그에 기록한다.

실측과 실행 방법은 `tools/pronunciation-spike/README.md`, 원시 보고서는 `.local/pronunciation-spike/`에 있다. Node 회귀 검사 355개와 서버 검사 10개, 다운로드·측정 self-check가 통과했다. 실제 마이크, 브라우저 화면, Android, 사람의 정상·오발음 정확도는 미검증이다. 커밋·push·배포는 수행하지 않았다.
