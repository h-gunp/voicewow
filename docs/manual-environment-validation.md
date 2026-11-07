# 수동 환경 수집 검증 기록

2026-11-08 수동 환경 수집·고정 기준선 변경을 검증했다. 이전 연속 자동 보정은 명시적 수집 방식으로 교체했으며 RNNoise와 VAD의 발화 표시 경로는 유지했다.

## 자동 검사

- `node --test tests/audio/*.test.mjs tools/prosody-web-tests/*.test.mjs tools/pronunciation-spike/*.test.mjs tools/asr-spike/*.test.mjs`: 435개 통과, 실패 0개다.
- `flutter test --reporter expanded`: 318개 통과, 실패 0개다.
- `flutter analyze --no-pub`: 문제가 없었다.
- `flutter build web --release --no-web-resources-cdn`: JavaScript release 빌드가 성공했다. 기존 flutter_tts Wasm dry-run 경고는 별개이며 Wasm 빌드를 검증한 결과가 아니다.
- `git diff --check`: 문제가 없었다.

Node 기록은 `.local/manual-environment-node.log`, Flutter 검사·분석·빌드 기록은 `.local/manual-environment-flutter-test.log`, `.local/manual-environment-flutter-analyze.log`, `.local/manual-environment-release-build.log`다.

## 확인한 경계

초기 idle, 버튼 전 큐 제외, 서로 겹치지 않는 500프레임, 400개 유효 표본, 클리핑 10% 경계, 사분위 범위 12dB 경계, 디지털 무음, 유한 최대 에너지 중앙값을 검사했다. 주변 대화와 uncertain 프레임을 환경 수집에 포함하면서 수집 중 발화 막대는 비우는 계약을 확인했다.

이전 성공 기준이 긴 발화·비발화에서 유지되고, 재측정 실패·사용자 취소에서도 보존되는 검사를 통과했다. 입력 끊김·오래된 프레임·기기/설정 변경·중지·재시작 뒤 늦은 이벤트는 기준을 폐기하거나 무시한다. level 이벤트만 오고 첫 analysis가 오지 않을 때의 무한 대기도 회귀 검사로 막았다.

Flutter에는 수집·취소·재측정·이전 기준 유지·요청 실패·지연 Promise·입력 설정 경계와 320px 너비/글자 2배 검사가 포함된다. 완료 직후 취소 Promise가 아직 끝나지 않은 동안 재수집을 열지 않는 경합도 확인했다.

설계, JS 처리, 최종 Dart/JS 통합을 독립적으로 검토했고 수정 필수 결함을 발견하지 못했다. 독립 검토자는 추가 경계 검사 9개와 11개를 각각 직접 실행해 통과를 확인했다.

## 배포와 미검증 범위

릴리스 웹 산출물은 135개 파일, 78,569,318바이트다. 발음 모델은 기존 GitHub 고정 자산 커밋에서 받으며 Sites 배포 파일에 포함하지 않는다. 배포 전 소스 커밋·원격 HEAD·정적 파일 해시를 대조하고 기존 공개 사이트에 게시한다. 실제 게시 결과의 최종 기록은 `.local/manual-environment-deployment.json`이다.

합성 입력·실제 WASM·위젯 검사는 실제 마이크와 다른 검사다. 아이폰 Safari, 실제 카페에서 수집 성공률, 기기별 적정 발성량과 기준선의 타당성은 검증하지 않았다. -60/10/3 보정 규칙과 품질 임계값은 제한된 실험값이며 SPL/dBA 교정이나 화자 식별을 의미하지 않는다.
