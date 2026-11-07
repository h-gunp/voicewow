# 기기 내부 발음 분석 검증 도구

제품 연결 전에 모델을 확인하려고 만든 검증 도구다. 녹음·WAV 입력을 기기 안에서 음소와 추정 한글로 변환한다. 이 spike 화면은 비교 색상이나 점수를 제공하지 않는다. 실제 발음 판별 정확도는 검증되지 않았다.

후속 요청에 따라 제품 앱은 이미 선다형 퀴즈를 발음 연습 상세 화면으로 교체했다. 사용자가 실제 음향 정확도를 추후 직접 검증하기로 했으므로 그 검증을 구현의 선행 조건으로 두지 않는다. 현재 제품 흐름과 저장 경계는 [발음 연습 문서](../../docs/pronunciation-training.md)에 있다. 기존 125개 콘텐츠 ID와 `voicemate.pronunciation.v1`의 북마크·개인 문장·과거 퀴즈 기록은 보존한다. 새 녹음 결과는 `recordAnswer`를 호출하지 않는다.

## 제품과 도구의 구분

제품은 목록·개인 문장·저장한 표현에서 같은 상세 화면을 열고, 사용자가 약 356MB 다운로드 안내를 확인한 뒤 ‘발음 모델 준비’를 눌러 준비한다. 마이크를 눌러 녹음하고 다시 누르거나 20초가 지나면 로컬 음소 추론과 Dart 비교를 수행한다. 모델이 추정한 발음과 참고 발음을 녹색·빨간색·회색으로 표시하며 재녹음·자신의 녹음 재생을 지원한다. 색상은 추정 결과의 일치·차이·보류를 뜻하며 실제 정오나 점수가 아니다.

제품 웹 구현은 `apps/client/web/pronunciation/`에 있다. 이 도구의 `phone-engine.mjs`, `phones.mjs`, `recording.mjs`, `audio.mjs`는 제품 모듈을 재수출하고 `client.mjs`는 제품 클라이언트에 spike의 로컬 Worker를 연결하여 같은 코드를 검사한다. Android는 같은 고정 모델·사전·CTC 규칙의 Kotlin ONNX 엔진으로 같은 음소 계약을 반환한다. 네이티브 구현은 Android 전용이며 다른 네이티브 플랫폼은 미지원 처리한다.

제품 웹의 첫 준비는 고정 Hugging Face revision의 설정·음소 사전과 같은 사이트에 배포한 ORT 모델 조각 22개를 내려받아 크기·해시를 검사하고 캐시한다. ORT는 기존 ONNX와 같은 가중치의 포맷 변환이며 추가 양자화나 텍스트 ASR 교체가 아니다. 아래 spike 서버와 기본 `measure.mjs`는 미리 받은 기존 ONNX 파일을 사용한다. 따라서 기본 spike 측정만으로 제품 웹의 ORT 로더·메모리 경로를 검증했다고 판단하지 않는다. 어느 경로도 사용자 음성·선택 문장·인식 결과를 외부 분석 서버에 업로드하는 API를 사용하지 않는다. 제품 예시 듣기는 로컬로 확인된 한국어 TTS만 선택하며 원격 음성으로 대체하지 않는다. 실제 기기에서 네트워크 차단 후 흐름과 외부 요청 부재를 관찰하는 검증은 남아 있다.

제품 웹 빌드 전에는 저장소 루트에서 `python tools/pronunciation-spike/prepare-web-model.py`를 실행하고 `--check`로 검증한다. 도구는 검증된 고정 ORT 원본을 16MiB 이하의 조각으로 배치하며, 원본이 없으면 공개 사이트의 고정 조각을 받는다. 조각은 Git에서 제외되지만 `apps/client/build/web/pronunciation/models/`에 복사된 22개 파일을 정적 배포에 모두 포함해야 한다. 모델 준비를 생략한 소스 전용 배포는 지원하지 않는다. 고정 해시와 최초 게시 조건은 [모바일 발음 안정성 기록](../../docs/mobile-pronunciation-stability.md)에 있다.

## 실행

저장소 루트에서 실행한다. 처음 설치할 때만 아래 다운로드가 필요하다. 모델 파일은 git에서 제외된 `.local/pronunciation-spike/`에 둔다.

```powershell
python tools/pronunciation-spike/download-model.py
python tools/pronunciation-spike/serve.py --port 8093
```

브라우저에서 `http://127.0.0.1:8093/`를 연다. `로컬 모델 준비` 뒤 마이크 버튼을 눌러 시작하고 다시 눌러 종료한다. 자동 종료는 20초다. 녹음 재생과 인식된 음소를 함께 확인한다. 16비트 PCM WAV 파일도 기기 안에서 읽을 수 있다. 창·탭 이탈과 취소는 녹음·분석을 정리한다.

서버는 IPv4 loopback과 정해진 정적 파일만 제공한다. 브라우저 분석 중 외부 URL은 사용하지 않으며 CSP도 같은 출처만 허용한다. 마이크는 사용자가 버튼을 눌러야 열린다. 녹음은 임시 메모리와 재생 객체에만 존재하며 재시도·이탈 시 정리한다.

초기 spike 작업에서는 서버의 임시 포트 단위 검사를 통과했다. 당시 장시간 실행할 검증 서버의 백그라운드 시작은 자동 승인 검토에서 `blocked by policy`로 거절됐다. 이는 과거 실행 기록이며 현재 서버가 실행 중이라는 뜻이 아니다. 위 명령은 재현 절차다.

## 2026-11-07 초기 spike 확인 결과

모델은 [chegrowk/ko-phone-int8](https://huggingface.co/chegrowk/ko-phone-int8)의 revision `dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70`이다. 원모델은 [slplab/wav2vec2-xls-r-300m_phone-mfa_korean](https://huggingface.co/slplab/wav2vec2-xls-r-300m_phone-mfa_korean)이다. 양쪽 카드가 Apache-2.0을 표시한다. 다운로드 도구가 원본·변환본의 설정 일치와 파일 무결성을 검사한다.

- ONNX 크기는 356,129,122바이트이며 SHA-256은 `c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134`다.
- 기존 vendored ONNX Runtime 1.23.2 WASM으로 실행됐다. 입력은 `input_values: float32[1,n]`, 출력은 `logits: float32[1,t,45]`다. 이 변환본에는 attention mask 입력이 없다.
- 음소 사전의 0–39는 실제 phone, 40은 음소 구분자, 41은 unknown, 42는 blank, 43·44는 추가 특수 토큰이다. config의 BOS/EOS 값 1·2를 제거하면 B/BB가 사라지므로 사용하지 않는다.
- `|`는 띄어쓰기나 음절 경계가 아니다. E는 ㅐ/ㅔ, iE는 ㅒ/ㅖ, oE는 ㅙ/ㅚ/ㅞ를 구별하지 않는다. 한글 표기는 가능한 대표값과 모호성 표시다. 원문을 넣어 이를 복원하지 않는다.
- uEO는 원모델 IPA 표의 표기 불일치 때문에 `□`로 보류한다. 음절로 조합할 수 없는 자음은 자모로 남긴다.

아래 값은 제품 연결 전 초기 spike의 역사적 측정이다. 측정 환경은 Windows, i5-13400F, Node 24.16.0, WASM 단일 스레드다. 현재 제품 브라우저·Android·휴대전화의 측정값이 아니다.

| 입력 | 추론 시간 |
| --- | ---: |
| 공개 음성 3.5265초, 첫 실행 | 2.237초 |
| 같은 음성 반복 | 3.991초 |
| 공개 음성 6.6281초 | 7.847초 |
| 공개 음성의 5초 앞부분 | 5.758초 |
| 공개 음성을 반복 연결한 20초 입력 | 27.225초 |

파일 검사 포함 엔진 준비는 1.108초, 프로세스 최대 RSS는 1,231,496KiB였다. 반복 실행이 항상 빠르거나 모바일 메모리에서 실행된다는 근거는 없다. 20초 반복 입력은 길이·자원 검사이며 자연스러운 발화 정확도 자료가 아니다.

무음은 거부했다. **5초 백색잡음은 `아`로 인식됐다.** `display.uncertain`은 한글 조립의 모호성만 나타내므로 이 경우 false여도 사람의 발화라는 뜻이 아니다. 이를 발음 신뢰도·정오 판정으로 사용하지 않는다. 제품에는 추정 음소 비교 색상을 연결했지만 실제 발음 판별 정확도는 검증 전이며 잡음이 글자로 인식될 수 있음을 화면에 표시한다. 사람의 정상·오발음과 잡음으로 성능을 검증하는 일은 사용자의 후속 검증으로 남아 있다.

공개 WAV 출처·해시는 `.local/pronunciation-spike/fixture-manifest.json`에 있다. 해당 파일의 참고 원문은 실제 소리를 사람이 음소 단위로 확인한 정답이 아니다. 저장소의 Yuna 가이드는 합성 음성이므로 실제 사람 평가 표본으로 취급하지 않았다.

## 검사와 산출물

2026-11-07 모바일 안정성 변경 후 Node 검사 407개와 Flutter 검사 304개가 통과했고 `flutter analyze`에서 문제가 없었다. JavaScript release 웹 빌드도 성공했다. 공개 WAV 2개를 새 세션 2개에서 총 5회 추론한 ORT·입력 해제 경로는 최대 RSS 912.45MiB였으며 기준 ONNX 경로의 1221.52MiB와 비교했다. logits 해시·음소·표시·프레임이 일치했다. 20초 반복 연결 입력은 최대 RSS 852.82MiB·추론 31.955초였다. 이는 로컬 Node 자원 검사이며 모바일 마이크나 자연 발화 정확도 검증이 아니다. 상세 근거는 [모바일 발음 안정성 기록](../../docs/mobile-pronunciation-stability.md)에 있다.

```powershell
node --test tools/pronunciation-spike/*.test.mjs
python tools/pronunciation-spike/serve_test.py
python tools/pronunciation-spike/download-model.py --self-check
node tools/pronunciation-spike/measure.mjs --self-check
node tools/pronunciation-spike/measure.mjs
```

다운로드 도구는 모델과 함께 고정 revision의 공개 예제 두 개를 받는다. 사용자 오디오를 업로드하지 않는다. 실측 스크립트는 기존 파일만 읽는다. 원시 녹음 또는 모델 가중치를 커밋하지 않는다.

초기 spike 당시 기록은 새 Node 검사 36개, 당시 기존 검사를 포함한 355개, Python 서버 검사 10개 통과다. 다운로드·측정 self-check와 실제 엔진의 동시 요청·종료 경계 4개도 확인했다. 이 수치는 현재 제품 회귀 검사 총계가 아니다.

모바일 안정성 변경 전 제품 연결 당시에는 Flutter 검사 303개, Node 제품 회귀 339개와 spike 회귀 36개 통과를 확인했으며 `flutter analyze`에서 문제가 없었다. 390px, 320px·글자 200%, 1280px의 합성 위젯 렌더링 3개도 통과하고 이미지를 확인했다. Kotlin 격리 컴파일과 PCM·CTC 관련 JVM 검사 4개를 통과했지만 전체 APK 빌드는 `No Android SDK found`로 완료하지 못했다. JavaScript release 웹 빌드는 54.9초에 성공했으며 기존 `flutter_tts`의 Wasm dry-run 경고만 남았다. 이 수치는 현재 변경의 최종 검사 총계가 아니다.

기존 제품 8092 서버의 `/?feature=pronunciation`, `/pronunciation/bridge.mjs`, `/main.dart.js`가 HTTP 200을 반환했고 `main.dart.js`의 응답 해시는 새 로컬 빌드와 일치했다. 새 서버를 시작하지 않았으며 이 HTTP 확인은 브라우저 마이크 실행이나 음향 검증이 아니다.

제품 `apps/client/web/pronunciation/phone-engine.mjs`를 직접 사용한 Node WASM 공개 WAV 추론도 성공했다. 입력은 3.5265초, 추론 시간은 3.880초이며 결과는 `.local/product-model-check.json`에 있다. 위 초기 spike 표와 별개의 제품 모듈 실행 결과다. 합성 위젯 렌더링과 Node 실행을 실제 마이크 검증으로 해석하지 않는다. 실제 브라우저·Android 기기의 마이크와 정상/오발음 판별 정확도는 미검증이다.

결과 파일은 `.local/pronunciation-spike/manifest.json`, `fixture-manifest.json`, `node-report.json`, `input-output-metadata.json`, `lifecycle-report.json`, `tests.log`다. `.local`은 버전 관리에서 제외된다.

## 남은 검증

현재 상태는 **로컬 모델 추론과 제품의 녹음·비교 흐름 구현, 실제 음향 정확도 미검증**이다. Flutter 목록·개인 문장·복습의 상세 화면 연결과 Android 구현은 이미 진행했으므로 향후 구현으로 나열하지 않는다.

사용자는 iPhone 16 Pro Safari에서 모델 다운로드 완료 뒤 마이크를 누르면 페이지가 새로고침된다고 보고했다. 로더 중복 버퍼와 런타임 모델 보관을 줄인 로컬 측정은 [모바일 발음 안정성 기록](../../docs/mobile-pronunciation-stability.md)에 분리했다. OS 종료 로그와 변경 후 실기기 검증이 없어 메모리 문제를 확정 원인으로 쓰거나 Safari 문제가 해결됐다고 기록하지 않는다.

사용자가 완성된 화면에서 `께/떼`, `써/떠`, 받침·연음, 허용 변이, 삽입·누락을 실제로 읽은 표본과 잡음을 구별하는 평가를 수행해야 한다. 실제 기기의 권한·마이크·녹음 재생, 5초·20초 추론 시간과 메모리, 취소·이탈·캐시 재사용, 네트워크 차단 후 동작도 별도 확인 대상이다. Android의 APK 빌드와 실제 기기 검증은 웹 또는 Node 실행 성공과 구분한다.
