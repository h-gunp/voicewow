# Full-feature design integration plan

> **For agentic workers:** Use the existing approved interface design, parallelize independent presentation files, and verify the integrated application before serving it locally.

**Goal:** 실행 중인 한 버전에 변경된 디자인과 음량 측정·발음 퀴즈·내 문장·복습·높낮이 연습을 함께 제공한다.

**Architecture:** 최신 `origin/main`의 기능과 화면 전환을 기준으로 기존 디자인을 이식한다. 오디오·저장소·퀴즈 데이터·분석 로직은 바꾸지 않는다.

**Tech Stack:** 기존 Flutter/Dart 및 높낮이 HTML/CSS다. 새 의존성은 없다.

**Spec:** `docs/superpowers/specs/2026-11-07-interface-design.md`와 이번 사용자의 기능 보존 및 디자인 통합 요청이다.

## Constraints and decisions

- 기존 수정 파일 11개는 SHA-256 확인된 `.local/design-integration-backup-20261107-150837` 및 Git stash에 보존했다.
- 현재 기능 브랜치를 `2abd55f`로 fast-forward했다. 통합 검증 단계에서는 브랜치 전환·새 커밋·push·공개 배포를 하지 않았다.
- 현재 main에서 제거된 화자 등록은 재도입하지 않는다. 기존 디자인의 색·정보 위계·반응형 구성만 적용한다.
- `fe26` 작업 폴더의 높낮이 툴바 변경은 복사해 포함하되 원본 폴더는 수정하지 않는다.
- 배경 `#fafaf7`, 글자 `#252a27`, 보조 글자 `#626b65`, 포인트 `#315b49`, 경계 `#d9ddd7`, 선택 배경 `#edf2ec`를 사용한다. 측정·피드백의 의미가 있는 색은 유지한다.
- Pretendard, 모든 기존 기능/Key/callback, 화면 전환 시 오디오 정리, 접근성 및 200% 글자 확대를 유지한다.

## Review focus

- 디자인 적용 후에도 세 하단 탭과 퀴즈·내 문장·복습이 접근 가능해야 한다.
- 320px 및 200% 글자에서 화면·조작이 넘치지 않아야 한다.
- 게이지의 애니메이션·하한/상한·음성 판정과 상대 입력 고지를 유지한다.
- 높낮이 iframe의 높이 계약·가이드/녹음/결과 전환·모델 파일 경로를 유지한다.
- 기존 미커밋 변경을 덮어쓰거나 소스와 다른 서버를 안내하지 않는다.

## Tasks

- [x] 공통 테마·탐색·목록형 상황 선택을 이식하고 모든 기능을 가진 화면의 회귀 테스트를 추가한다.
- [x] 최신 측정 계산과 동작을 유지하며 게이지·측정·진단 디자인을 이식한다.
- [x] 발음 퀴즈·내 문장·복습의 표현을 같은 테마로 정리한다.
- [x] 높낮이 웹 표현에 같은 테마와 기존 모바일 툴바 변경을 적용한다.
- [x] Flutter/Node 테스트·정적 분석·웹 빌드·렌더링 검증과 독립 리뷰를 완료한다.
- [x] 현재 프로젝트의 `8092` 서버에 통합 빌드를 제공하고 HTTP 및 제공 파일을 확인한다.

## Verification record

- 데스크톱 선택 행 너비 회귀 테스트는 이식 전 274px로 실패했고 이식 후 통과했다.
- 전체 Flutter 테스트 278개와 Node 테스트 319개가 통과했다. Flutter analyze는 오류가 없다.
- 200% 글자에서 기준선 라벨 겹침을 발견하여 확대 시 기존 310px 기준 높이를 유지했다. 기존 해당 회귀 테스트를 포함해 통과했다.
- 측정의 단일 범위 Tween과 비교 gate를 유지하면서 모바일 주 제어를 환경 상세보다 먼저 배치했다. ready 상태 위치 검사도 통과했다.
- 390×844 및 1280×900의 Flutter 테스트 렌더링 12장을 생성해 확인했다. 입력값은 FakeAudioPort 합성값이다.
- 독립 리뷰에서 발견된 라벨 겹침 및 신규 테스트 문자열 손상은 수정 후 재검증했다.
- 실제 브라우저 iframe 렌더링·마이크·음향 정확도는 자동 테스트 및 Flutter 렌더링으로 검증한 것이 아니다.
- 최종 JavaScript release 웹 빌드는 exit 0이다. 의존성의 선택적 Wasm dry-run 경고는 이 JavaScript 빌드 실패가 아니다.
- `http://127.0.0.1:8092/`의 메인 HTML·JS·높낮이 HTML·CSS·JS 5개 경로가 HTTP 200이고 로컬 빌드와 SHA-256이 같다. 높낮이 CSS는 현재 소스와도 바이트가 같다.
- 제공 JS의 발음 훈련·발음 퀴즈·높낮이 연습 문자열을 확인했다. 실행 근거는 `.local/integrated-runtime.json`이다.
- 별도 `8787` 서버 교체 명령은 정책상 차단되어 실행되지 않았다. 기존 현재 프로젝트 `8092` 서버가 통합본을 제공하므로 프로세스 교체 없이 실행을 완료했다.

## Commit and push request

2026-11-07 사용자가 현재까지의 변경을 커밋하고 푸시하도록 요청했다. 대상은 `origin`의 `h-gunp/voicewow` 저장소와 현재 `codex/enrollment-first` 브랜치다. 코드·테스트·설계 기록 18개 파일을 포함하며 `.local` 백업·검증 로그·생성 빌드는 포함하지 않는다. 이 요청은 `main` 병합이나 공개 사이트 배포를 포함하지 않는다.
