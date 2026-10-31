# VoiceMate

상황별 고정 기준과 마이크 입력 수준을 보여주는 Flutter Web 앱이다. RNNoise로 주변 소음을 줄인 뒤 음량을 계산하며, 음성은 브라우저 메모리에서 처리한다.

## 실행 환경

Flutter 3.47.7과 함께 제공되는 Dart를 사용한다. Node.js와 Python 3도 필요하다. 의존성은 apps/client/pubspec.lock에 고정되어 있다.
Windows 실행 스크립트를 사용하려면 Flutter SDK를 저장소의 .tools/flutter에 설치한다. SDK와 빌드 결과는 커밋하지 않는다.

```powershell
Push-Location apps/client
& ../../.tools/flutter/bin/flutter.bat pub get
& ../../.tools/flutter/bin/flutter.bat test
& ../../.tools/flutter/bin/flutter.bat analyze
& ../../.tools/flutter/bin/flutter.bat build web --release --no-web-resources-cdn
Pop-Location
node --test tests/audio/*.test.mjs
.\scripts\start-web.ps1
```

## 구조와 동작

lib/screens와 lib/widgets는 화면, lib/session_controller.dart는 상태와 표시값, lib/audio와 web/audio는 입력을 담당한다.
표시값은 clamp(dBFS + 114, 0, 120)이다. 무음 프레임은 0, 입력 없음은 빈 막대와 —로 표시한다.
+114는 사용자가 실험에서 웹사이트 측정값과 앱의 보정 전 값 사이 차이를 직접 관측해 얻은 보정값이다. 기준 소음계로 절대 SPL을 교정한 결과나 모든 기기·입력 경로의 유효성을 뜻하지 않는다.
고정 기준은 조용한 대화 53–75, 소음 있는 대화 58–80, 회의실 68–78, 강당 65–75다.
빨간 기준선과 150ms easeOut으로 채워지는 파란 막대를 사용한다. 별도 영역에는 실험적인 주변 잡음·발화 추정과 환경 변화에 따른 참고범위를 표시한다. 개인 기준 등록이나 본인 화자 식별은 없다.
실제 SPL/dBA로 보정한 계측기가 아니며, 주변 소리와 타인의 목소리도 포함된다.

## 소음 억제

기본값은 켜짐이다. 화면의 주변 소음 억제 스위치를 끄면 RNNoise 로딩 없이 원본 입력을 측정한다. 실행 중 전환하면 입력을 재시작하며 이전 입력값을 지운다. 선택은 중지·재시작·상황 변경 동안 유지된다.

입력은 마이크 → `noise-reduction-worklet.mjs`의 RNNoise·LevelMeter → `capture-bridge.mjs` → WebAudioPort → SessionController → 화면 순서로 전달된다.
앱에 포함한 `@jitsi/rnnoise-wasm@0.2.1`의 비동기 로더와 RNNoise 0.1 기본 모델을 같은 사이트에서 불러온다. API 키나 별도 서버가 필요하지 않으며 원본 음성을 저장·업로드하지 않는다. 파일 출처·해시·라이선스는 [RNNoise 자산 기록](apps/client/web/audio/vendor/rnnoise/README.md)에 있다.

- 48,000 Hz AudioContext를 요청하고 480개 표본(10ms)씩 처리한 뒤 기존 100ms 음량 계산에 전달한다. 표시 오프셋 114와 네 상황의 기준은 유지한다.
- 준비 중에는 측정값을 표시하지 않는다. 초기 모듈·WASM 로딩 실패, 10초 제한 시간 초과, 지원하지 않는 샘플레이트에서는 기존 `capture-worklet.js`로 원본 입력을 측정하고 화면에 안내한다.
- 적용 중 처리 오류는 측정을 종료하고 재시작 안내를 표시한다. 취소·중지·탭 이탈·입력 장치 변경 시 마이크와 노드를 해제한다.
- 입력 정보에 앱 소음 억제 상태와 처리 후 dBFS를 표시한다. 적용하지 못하면 원본 dBFS이며, 중지·오류 상태에서는 미사용으로 표시한다.

소음 억제는 음성 성분의 크기도 바꿀 수 있으므로 처리 전 수치와 동일하지 않다. 발화 판정과 잡음 추정은 미검증 실험 기능이며 타인 음성을 구별하지 못하고 발화를 놓칠 수 있다. 실제 음압 보정이나 Krisp와 동등한 성능을 검증한 결과가 아니다. 실제 사용자 발화와 iPhone Safari 동작은 별도 확인이 필요하다.

자동 조절은 선택한 상황을 기준으로 시작한 뒤 같은 세션의 지속적인 환경 변화만 추적한다. 시작부터 시끄러운 환경을 자동 분류하지 않는다. 입력 설정의 AGC·브라우저 잡음 억제·반향 제거가 모두 꺼졌다고 확인된 경우에만 분석한다. 임계값과 상한은 실험값이며 안전한 음압을 뜻하지 않는다. 자세한 경계는 [설계 문서](docs/environment-adaptation.md)에 있다.

## 검증과 배포

RNNoise 상태 안내·초기화·취소·시간 초과·원본 복귀 검사를 포함한 테스트의 예상 수는 Flutter 39개와 Node 94개다. Node 테스트 일부는 포함된 실제 WASM의 무음·잡음·프레임 경계를 검사하며 실제 사용자 발화 검증을 대체하지 않는다. 실제 통과 여부는 실행 결과로 확인한다.
배포 대상은 apps/client/build/web 전체이며 HTTPS와 JavaScript 모듈 MIME이 필요하다. RNNoise의 모듈·WASM·라이선스 파일도 함께 배포한다.
하위 경로에 배포하면 해당 경로로 --base-href를 설정해 다시 빌드한다. 아이폰 Safari의 실제 마이크 검증은 자동 테스트와 별도로 수행한다.
개발 원본은 이 GitHub 저장소다. 기존 Sites 주소를 유지하고, 이 저장소의 검증된 커밋으로 만든 웹 산출물만 배포한다. [배포 절차](docs/deployment.md)를 따른다. 계정·자격증명·개인 실험 자료·빌드 산출물은 이 저장소에 커밋하지 않는다.
제3자 고지는 THIRD_PARTY_NOTICES.md에 있다.
