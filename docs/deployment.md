# 단일 소스와 Sites 배포

개발 원본: https://github.com/h-gunp/voicewow
기존 서비스: https://voicemate-microphone.hongskrr.chatgpt.site

GitHub의 소스를 수정하고 검증한 뒤 그 커밋에서 Flutter Web을 빌드한다. Sites 저장소는 배포 산출물을 전달하는 목적이며 별도 기능 개발 원본으로 사용하지 않는다. 양방향 자동 동기화는 아니다.

1. 깨끗한 작업 브랜치에서 기존 테스트, 정적 분석, 릴리스 빌드를 수행한다. Flutter 버전은 `.flutter-version`, 의존성은 `apps/client/pubspec.lock`을 따른다.
2. 변경을 검토하고 GitHub에 커밋·반영한다. 배포할 정확한 40자리 소스 SHA와 테스트 결과를 기록한다. 캐시·개인 자료·자격증명·build는 올리지 않는다.
3. 기존 Sites 프로젝트를 조회하고 현재 audience를 유지한다. 기존 `.openai/hosting.json`의 프로젝트 ID와 `static.directory`를 보존한다. Sites 스킬의 source helper로 별도 체크아웃을 연다. 단기 자격증명은 메모리와 helper의 숨겨진 stdin에서만 다룬다.
4. 해당 GitHub 소스 SHA에서 생성한 `apps/client/build/web` 전체를 Sites의 `dist`에 반영한다. 예전 파일이 섞이지 않게 파일 목록과 SHA-256을 대조한다. RNNoise WASM·모듈·라이선스를 포함한다.
5. Sites 저장소 루트의 `github-source.json`에 GitHub repository, commit, Flutter version, 그리고 dist의 파일별 SHA-256을 기록한다. 이것은 배포 출처이며 토큰이나 사용자 데이터를 포함하지 않는다.
6. source helper로 정확한 정적 저장소 상태를 커밋·푸시·패키징한다. 반환된 Sites commit SHA와 archive로 버전을 저장하고 기존 사이트에 배포한다.
7. GitHub SHA / Sites SHA / Sites 버전·배포 ID / URL / 검증 범위를 로컬 배포 영수증으로 기록한다. 배포 성공 응답과 기존 UI를 확인한다. 실제 마이크·iPhone 검증은 자동·합성 테스트와 구분한다.

## 2026-10-31 통합 범위

GitHub main `0df831a6fe644296b5a84e97ba7b4495b9cfc13e`를 기준으로 기존 로컬 앱의 RNNoise ON/OFF 토글, 전환 수명 처리, 동일 마이크의 장치 목록 노출 처리 및 해당 테스트를 보존했다. 원본 작업본과 미추적 자료는 별도 로컬 보존본에 남겼다. 기존 표시 오프셋 114와 고정 상황 범위는 유지한다.

소음 추정, VAD, 환경에 따른 자동 목표 조절은 이 통합에 포함하지 않는다. 후속 설계로 진행한다. +114는 비교로 얻은 표시 오프셋이며 교정 소음계 기반 SPL 정확도를 의미하지 않는다.
