# 발음 훈련

발음 훈련은 apps/client/lib/features/pronunciation에 모은 독립 기능이다.
앱 하단 ‘발음 훈련’으로 들어가며, 웹에서는 /?feature=pronunciation으로 바로
열 수 있다. Android는 발음 훈련으로 시작한다. 기존 음량 측정의 마이크
구현은 웹 전용이며 이번 발음 기능의 Android 지원과 별개다.

## 사용자 흐름

- **발음 퀴즈:** 단어 / 기초 문장 / 확장 문장 / 비즈니스 문장 → 하위 분류와
  표현 선택 → 두 보기 중 올바른 읽는 소리 선택 → 정답·설명 → 다음 문제·결과.
- **내 문장:** 300자 이내 문장 입력 → 읽는 소리와 변화 설명 → 보통/느린
  예시 음성 → 저장한 문장 다시 연습.
- **복습:** 틀린 문제와 저장한 문제를 다시 푼다. 맞힌 오답은 오답 목록에서
  빠지며 저장 표시는 유지된다.

보기 순서는 문제를 시작할 때 섞고, 화면이 갱신될 때는 바꾸지 않는다.
정답 확인 전에는 예시 음성을 제공하지 않는다. 복습 기록과 문장 저장은
기기 또는 해당 브라우저에 남으며 로그인·서버 동기화는 없다.

## 콘텐츠와 발음 변환 범위

각 상위 분류에 8개씩, 총 32개의 직접 작성한 초기 문제가 있다.
domain/quiz_catalog.dart의 설명과 sourceUrl은 국립국어원 자료를 기준으로
작성했다. 문장 보기는 어절별로 나누어 읽는 연습 기준이며 어절 사이의
선택적인 이어 읽기나 소리의 길이를 정답 판정에 포함하지 않는다.
기존 상용 서비스의 문제·이미지·음성은 복사하지 않았다.

domain/pronunciation_guide.dart는 순수 Dart로 동작한다.
연음, 받침 대표음, 구개음화, 거센소리, 비음화, 유음화, 된소리와 일부
단어 예외를 지원한다. 띄어쓰기·문장부호·숫자·영문은 보존한다.
형태소·문장 의미 분석, 고유 명사, 모든 합성어 예외, 띄어쓰기 너머의 변화,
장단음·억양까지 해결하는 전체 한국어 사전은 아니다. 일부 중의적인 말은
발음을 단정하지 않고 추가 안내를 표시한다. 출력은 **규칙 기반 참고**이며
사용자 목소리의 발음 자동 평가나 채점은 하지 않는다.

변환 자체에는 API 키나 네트워크가 필요하지 않다. 예시 음성은 flutter_tts로
브라우저/Android의 한국어 음성을 사용한다. 한국어 음성이 없거나 재생이
실패하면 텍스트 안내를 유지한다. 기기 음성 엔진은 설정과 제공자에 따라
네트워크를 사용할 수 있으므로 완전한 오프라인 음성 재생을 보장하지 않는다.

## 통합 지점

- app.dart: 기존 음량 화면과 발음 훈련 사이의 탐색. 발음으로 이동하면
  진행 중인 마이크 입력을 먼저 중지한다.
- data/learning_store.dart: 버전이 있는 JSON 기록, 순서대로 저장하는 큐,
  저장 실패 시 메모리에서 연습 지속. 앱 범위의 controller를 유지하므로
  화면 재진입이 저장 중인 기록을 덮어쓰지 않는다.
- data/speech_player.dart: 재생·취소·한국어 음성 미지원 구분.
- presentation/: 분류·퀴즈·결과·개인 문장·복습 화면.

공용 앱 진입점과 패키지 의존성 외의 기존 음량 처리 코드는 변경하지 않는다.
팀 통합은 PR 검토 후 저장소 관리자가 진행한다.

## 웹 실행과 검사

저장소의 .flutter-version에 맞는 Flutter 3.47.7을 사용한다.
설치된 Flutter가 PATH에 없다면 아래 flutter를 SDK의 절대 경로로 바꾼다.

    cd apps/client
    flutter pub get
    flutter analyze
    flutter test --no-pub
    flutter build web --release --no-web-resources-cdn
    flutter run -d chrome

웹 배포 산출물은 apps/client/build/web 전체다. 현재 사용하는 TTS 플러그인은
Wasm dry-run 경고가 있어, 검증 대상은 기본 JavaScript 웹 빌드다.
실제 사용자 발음의 적절성 검증과 기기별 TTS 음질 확인은 별도로 필요하다.

## Android

Android 프로젝트는 같은 apps/client 안에 있다. applicationId는 개발용
com.voicewow.voicemate, 최소 Android API는 24다. JDK 17과 SDK 36을 사용하며
Gradle·AGP는 Flutter 3.47.7의 생성값을 유지한다. SDK·개인 환경 경로·서명 키는
커밋하지 않는다.

Windows의 Gradle 9.3.1/JDK 17 조합에서는 한글이 포함된 캐시 경로가 Kotlin
설정 파일 컴파일 오류를 일으킬 수 있다. 이 경우 GRADLE_USER_HOME을 실제
영문 폴더로 지정한다. 영문 이름의 junction이 한글 폴더를 가리키는 경우도
피한다. [Gradle 관련 이슈](https://github.com/gradle/gradle/issues/35572).
JDK·SDK·NDK·CMake 역시 실제 영문 경로에 설치한다. 한글을 포함한 SDK 경로가
CMake의 ninja 실행 경로에 잘못 기록되는 Windows 환경이 있다.

    cd apps/client
    flutter devices
    flutter run -d <Android-device-id>
    flutter build apk --debug --target-platform android-arm64

디버그 APK는 테스트 설치용이며 스토어 배포용 서명·패키지 이름은 팀에서
정해야 한다. 기존 웹의 음량 측정을 Android 네이티브로 옮기는 작업은
이 발음 기능의 APK 빌드와 분리된 후속 작업이다.
