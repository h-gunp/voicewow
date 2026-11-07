# Pronunciation Practice Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development. Steps use checkbox syntax for tracking.

**Goal:** 기존 선다형 퀴즈를 저장 표현 선택·녹음·로컬 음소 추론·색상 비교·재연습 흐름으로 교체한다.

**Architecture:** 검증 도구의 PCM·CTC 코드를 제품 웹 경로로 옮겨 재사용한다. Flutter 공통 화면과 순수 Dart 음소 비교를 사용하고, 웹 JS 브리지와 Android ONNX 채널이 동일한 음소 목록을 반환한다. 기존 저장 스키마와 음량·높낮이 기능은 유지한다.

**Tech Stack:** Flutter/Dart, 기존 ONNX Runtime Web, Android ONNX Runtime, 기존 record/just_audio/TTS다.

**Spec:** `docs/superpowers/specs/2026-11-07-local-pronunciation-check-design.md` 및 후속 사용자 지시다.

## Global Constraints

- 실제 발음 검증은 사용자가 후속 수행한다. 이를 이유로 구현을 다시 멈추거나 승인을 반복 요청하지 않는다.
- 음성은 기기 밖으로 보내지 않는다. 고정 revision의 공개 모델만 최초 다운로드·해시 확인·캐시한다.
- 비교 색은 추정 인식과 참고 읽기의 일치/차이다. 음향 정확도·점수·확률을 주장하지 않는다.
- 20초 자동 종료, 최종 샘플 포함, 취소·연타·화면 이탈·늦은 결과 정리를 유지한다.
- 125개 기존 콘텐츠 ID, 북마크, 개인 문장, 과거 퀴즈 기록을 보존한다. 새 결과를 이전 정답 기록에 쓰지 않는다.
- 현재 작업 브랜치에서 변경하며 다른 worktree, 기존 서버 프로세스, 사용자 데이터를 변경하지 않는다. 이전에 거절된 서버 시작은 재시도하지 않는다.

## Review Focus

- 녹음 중 다른 기능으로 이동해도 마이크가 남지 않는다: Task 1/3/4에서 검사한다.
- 한 음소 누락이 뒤 문장 전체를 오답 색으로 밀지 않는다: Task 2에서 검사한다.
- ㅐ/ㅔ, ㅒ/ㅖ, 허용 변이와 불완전 자모는 정답에서 복원하지 않는다: Task 2에서 검사한다.
- 모델 다운로드/권한 대기/추론 중 취소 후 새 요청에 이전 콜백이 섞이지 않는다: Task 1/3/4에서 검사한다.
- 기존 개인 문장·북마크·음량·높낮이와 글자 200% 접근성을 유지한다: Task 4/5에서 검사한다.

### Task 1: 공통 녹음 계약과 웹 추론

Files: `apps/client/lib/features/pronunciation/data/pronunciation_recorder{,_contract,_web,_native,_stub}.dart`, `apps/client/web/pronunciation/`, `apps/client/web/index.html`, 관련 Node 검사다.

Interface: `PronunciationRecorder.prepare({void Function(String)? onProgress})`, `start({required void Function() onLimit, required void Function(String) onError})`, `finish(): Future<List<String>>`, `play()`, `cancel()`, `dispose()`다. prepare/start/play/cancel/dispose는 Future<void>다. factory는 `createPronunciationRecorder()`다.

- [x] 실패 테스트를 먼저 두고 기존 검증 도구의 engine/phones/recording/audio/client를 제품 경로로 재사용한다. 도구는 제품 모듈을 재export해 중복 구현을 없앤다.
- [x] 웹 global `voiceMatePronunciation`는 prepare(progress), start(onLimit,onError), finish(), play(), cancel(), dispose()를 제공한다. finish는 음소 문자열 배열만 반환한다. 마이크 준비나 추론을 자동 시작하지 않는다.
- [x] 공개 모델 캐시·해시 검사, 진행 안내, 실패 복구·마지막 PCM·세션 취소를 검증한다. 기존 TTS transport에 localOnly 선택을 추가한다.

### Task 2: 순수 Dart 음소 비교

Files: `apps/client/lib/features/pronunciation/domain/pronunciation_comparison.dart`, `apps/client/test/pronunciation_comparison_test.dart`다.

Interface: `comparePronunciation({required List<String> phones, required List<String> references, bool referenceIsApproximate=false}) -> PronunciationComparison`. 결과에는 `String reference`, `List<PronunciationSpan> observed`, `List<PronunciationSpan> expected`, `List<String> notes`, `List<String> differences`가 있다. span은 `String text`, `ComparisonMark mark`이며 mark는 match/different/uncertain다.

- [x] 대치·삽입·탈락·허용 기준 선택·반복 정렬·불완전 음절·모음 합류·무음 테스트를 먼저 작성한다.
- [x] 실제 phone에서 추정 한글을 조립하고, 기준 읽기를 음소로 바꾸어 동적 계획 정렬한다. 표기 모호성은 회색으로 남긴다. 같은 삽입/삭제 비용의 모호한 정렬을 확정 색으로 칠하지 않는다.
- [x] '마딛께/마싣께' 두 허용 변이와 사용자 예시 '께/떼', '써/떠'를 검사한다. 규칙 기반 개인 문장은 참고 기준임을 표시한다.

### Task 3: Android 연결

Files: recorder_native.dart, Android MainActivity·ONNX helper·Gradle, native transport localOnly, 관련 Dart/가능한 JVM 검사다.

- [x] 기존 DeviceAudioService 16kHz PCM과 로컬 재생·정리를 재사용한다.
- [x] Kotlin 채널 `voicemate/pronunciation`의 prepare/recognize/cancel/dispose를 구현하고 고정 모델 다운로드·무결성·백그라운드 추론·세대 취소를 처리한다. ONNX는 현재 웹과 같은 1.23.2를 고정한다.
- [x] 동일 vocab/blank/정규화/최대 길이를 사용하고 원문은 모델 입력에 넣지 않는다. 네이티브 빌드 가능 여부와 실기기 검증을 구분한다.

### Task 4: Flutter 사용자 흐름 교체

Files: pronunciation_screen.dart, quiz_training_view.dart, 새 pronunciation_practice_view.dart, app.dart, speech_player.dart, 관련 Flutter 테스트다.

- [x] 카테고리·목록·북마크·과거 복습을 유지하면서 선택지·퀴즈 제출·점수 화면을 제거한다. 선택한 표현을 새 상세로 연결한다.
- [x] 내 문장 가이드와 저장한 문장 선택도 같은 상세로 연결한다. 준비→녹음→종료 분석→색상 결과→재시도·재생을 구현한다.
- [x] TTS 중지 후 녹음을 시작하고 기능·탭·문장 이동·뒤로가기에서 취소를 기다린다. 결과는 메모리에서만 유지한다.
- [x] 모의 recorder를 주입해 정상 흐름, 오류, 취소, 저장 기록 불변, 초록/빨강/회색, 320px·글자 200%를 검증한다.

### Task 5: 통합 검증

- [x] Flutter test/analyze, Node 회귀, JavaScript release 웹 빌드를 수행한다. 가능하면 Android debug build도 수행한다.
- [x] 새 모듈을 사용한 실제 모델 공개 WAV 추론을 1회 확인한다. 실제 발음 정확도는 사용자 검증으로 남긴다.
- [x] 독립 리뷰로 생명주기·비교·네트워크 경계를 점검하고 발견된 결함을 고친다. 기능과 미검증 범위를 문서에 기록한다.

## 진행 기록

시작 상태: `530895d`, 이전 검증 도구와 승인 문서가 untracked다. 모델은 `.local/pronunciation-spike`에 검증된 상태로 존재한다. 제품 정확도 미검증을 숨기지 않으며, 사용자의 후속 지시에 따라 제품 구현을 진행한다.

완료 상태: 카탈로그·북마크·개인 문장·저장 문장을 새 녹음 상세에 연결했다. 별도 준비 버튼으로 모델을 내려받고, 하단 버튼으로 녹음 시작·종료 후 추정 발음과 참고 발음을 비교한다. 일치·차이·불확실을 색상과 범례로 구분하며 차이에는 밑줄을 붙인다. 녹음 재생·다시 읽기·취소·화면 이탈을 구현했다. 기존 v1 학습 데이터와 음량·높낮이 기능은 유지한다.

검증 근거:
- Flutter 전체 303/303, `flutter analyze --no-pub` 문제 없음이다.
- `npm test` 339/339, 발음 spike Node 36/36, Kotlin JVM 4/4다. 독립 웹·네이티브 리뷰에서 발견한 재생 조기 반환과 오래된 녹음 시작 경쟁을 수정했다.
- JavaScript release 웹 빌드를 완료했다. 기존 flutter_tts의 Wasm dry-run 경고는 남으며 Flutter Wasm 빌드를 검증한 것은 아니다.
- 제품 `phone-engine.mjs`로 공개 3.5265초 WAV를 실제 추론했다. 단일 Node WASM 추론은 3.880초다. `.local/product-model-check.json`에 결과가 있다. 이는 사람 발음 정확도나 모바일 성능 검증이 아니다.
- 390px·1280px 및 320px 글자 200%의 합성 Flutter 화면을 렌더링하고 확인했다. `.local/pronunciation_preview/` 이미지이며 브라우저·실기기 캡처가 아니다.
- 기존 `http://127.0.0.1:8092/?feature=pronunciation`이 새 웹 산출물을 제공한다. main.dart.js의 HTTP 응답과 로컬 빌드 SHA-256이 `d843a6fcd8ed2d586f63264dcde38607edb81a05ed56291a785b79dd88609df8`로 일치한다. 새 서버를 시작하지 않았다.
- Android Kotlin은 실제 ORT AAR·Flutter.jar를 이용해 독립 컴파일했다. `flutter build apk --debug --no-pub`는 `No Android SDK found`로 APK를 만들지 못했다.

남은 검증: 사용자 실발화의 정상·오발음 구별, 실제 브라우저·휴대전화 마이크와 다운로드·성능, Android SDK 환경의 APK 빌드·실기기 실행이다. 사용자가 실제 발음 판별 검증을 직접 수행하겠다고 지정한 범위는 완료로 표기하지 않는다.
