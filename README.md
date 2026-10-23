# VoiceMate

상황별 고정 기준과 마이크 입력 수준을 보여주는 Flutter Web 앱이다. 음성은 브라우저 메모리에서 처리한다.

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
고정 기준은 조용한 대화 53–75, 소음 있는 대화 58–80, 회의실 68–78, 강당 65–75다.
빨간 기준선과 150ms easeOut으로 채워지는 파란 막대를 사용한다. 개인 기준 등록이나 자동 적정 음량 판정은 없다.
실제 SPL/dBA로 보정한 계측기가 아니며, 주변 소리와 타인의 목소리도 포함된다.

## 검증과 배포

제공된 기준 테스트의 예상 수는 Flutter 24개와 Node 43개다. 실제 통과 여부는 실행 결과로 확인한다.
배포 대상은 apps/client/build/web 전체이며 HTTPS와 JavaScript 모듈 MIME이 필요하다.
하위 경로에 배포하면 해당 경로로 --base-href를 설정해 다시 빌드한다. 아이폰 Safari의 실제 마이크 검증은 자동 테스트와 별도로 수행한다.
이 저장소에는 기존 프로젝트의 배포 계정·사이트 ID·검증 영수증을 복사하지 않는다.
제3자 고지는 THIRD_PARTY_NOTICES.md에 있다.
