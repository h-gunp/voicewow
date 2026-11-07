# 모바일 발음 안정성 기록

2026-11-07 사용자는 [공개 VoiceMate 사이트](https://voicemate-main-20261103.hongskrr.chatgpt.site)의
발음 기능을 iPhone 16 Pro Safari에서 사용할 때 모델 다운로드 완료 뒤 마이크를 누르면
페이지가 새로고침된다고 보고했다. iOS 버전, OS 프로세스 종료 로그, Safari 오류 로그는
확보하지 않았다. 현재 근거는 사용자 재현 보고와 로컬 메모리 측정이다.

기존 경로에서 대형 모델 버퍼가 중복되는 문제를 확인해 줄였다. 메모리 압박은
새로고침 원인의 가설이며, 변경 후 실제 iPhone에서 해결됐다는 확인은 없다.
이 문서의 로컬 검사 결과만으로 공개 사이트의 게시 완료나 실기기 성공을 판단하지 않는다.

## 모델과 실행 계약

원본은 `chegrowk/ko-phone-int8`의 revision
`dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70`이다. 추가 양자화·학습·ASR 모델 교체는 하지 않았다.
16kHz 모노 PCM의 정규화, `input_values` 입력, 45개 음소의 `logits` 출력과 CTC 규칙을 유지한다.
기준 문장을 인식 입력으로 넣거나 인식한 음소를 정답 문장으로 교정하지 않는다.

| 용도 | 파일 | 크기 | SHA-256 |
| --- | --- | ---: | --- |
| Android·기본 spike | `onnx/model_quantized.onnx` | 356,129,122바이트 | `c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134` |
| 제품 웹 | `ko-phone-int8.ort` | 356,216,776바이트 | `a280f2679f08c809ae3c5ad55abe15dc78803e06143cc9b485c143612652765e` |

ORT 파일은 Python ONNX Runtime 1.31.0의 extended 최적화로 직렬화한 고정 산출물이다.
웹 실행기는 ONNX Runtime Web 1.23.2다. 변환기와 실행기 버전이 같다고 가정하지 않고,
실제 웹 WASM 실행기로 공개 WAV `0.wav`·`2.wav`의 logits 해시와 음소·프레임 결과를 비교했다.
이 입력들에서 일치한 결과를 모든 발음이나 기기의 정확도로 일반화하지 않는다.

## 메모리 변경

- `sha256.mjs`는 hash-wasm 4.12.0의 SHA-256으로 256KiB씩 검증한다. 로더와 엔진의 무결성 검증을 유지한다.
- 캐시는 모델 전체를 `Response(bytes)`로 복사하는 대신 256KiB 이하의 뷰를 스트림으로 전달한다. 캐시 기록이 끝난 뒤 엔진에 소유권을 넘긴다.
- 제품 Worker는 같은 가중치의 ORT 모델을 직접 참조하도록 연다. 발음 전용 JS 런타임은 직접 참조하는 WASM 모델 버퍼를 세션 종료까지 보존하고 한 번만 해제한다. 기존 높낮이 기능의 JS 런타임은 수정하지 않는다.
- `voicemate_consume_model_bytes=1`은 검증·캐시 저장을 마친 단독 소유 입력에만 사용한다. 전체 ArrayBuffer를 가리키는 Uint8Array이고 `ArrayBuffer.transfer`를 사용할 수 있으면 WASM 복사 뒤 JS 입력을 detach한다. 공유 버퍼·부분 뷰·미지원 환경에는 기존 보관 경로를 사용한다. 이후 세션 생성이 실패해도 입력이 이미 detach됐을 수 있다.
- 다운로드 100%와 엔진 준비 완료를 구분한다. 검증 뒤에는 모델을 여는 중임을 표시하고, 세션 준비가 끝난 뒤에만 마이크 시작을 허용한다.
- 녹음 재생 오류 등으로 취소할 때 이전 결과를 비운다. 폐기된 녹음에 이전 결과의 재생 버튼이 남는 상태를 막는다.

## 로컬 측정과 한계

다음 값은 Windows의 Node 24.16.0·WASM 단일 스레드에서 측정한 프로세스 최대 RSS다.
MiB는 1,048,576바이트다. 서로 다른 실험 범위를 한 번의 종합 측정처럼 합산하지 않는다.

| 실험 범위 | 이전 | 변경 후 | 근거 |
| --- | ---: | ---: | --- |
| 실제 ONNX 파일의 로더만 실행 | 1421.04MiB | 464.07MiB | `loader-memory-summary.json` |
| 같은 로더에서 ONNX 초기화·공개 WAV 추론까지 실행 | 1456.45MiB | 1207.88MiB | `loader-memory-summary.json` |
| 공개 WAV 2개·새 세션 2개·총 5회 추론, 단독 소유 입력 해제 포함 | 1221.52MiB | 912.45MiB | `mobile-runtime-regression-baseline.json`, `mobile-runtime-regression-consume.json` |

첫 두 행은 별도 Node 프로세스에서 실제 356MB 모델을 읽었다. fetch는 256KiB로 제한한
파일 스트림, Cache API는 디스크에 순차 기록하는 모의 구현이다. 음소·프레임·표시 결과는
같았으며, 실제 브라우저 캐시의 메모리 사용량을 측정한 것은 아니다.

세 번째 행은 ORT 직접 참조·버퍼 수명 패치와 단독 소유 입력 해제를 함께 적용한 측정이다.
공개 WAV `0.wav`·`2.wav`를 새 세션 2개에서 총 5회 추론했고, 각 입력의 logits 해시·음소·
한글 표시·프레임이 기준 결과와 일치했다. Node Worker를 추론 중 종료한 뒤 새 Worker에서
같은 logits 해시를 얻은 기록은 `mobile-runtime-worker-report.json`에 있다.

공개 WAV를 인위적으로 반복 연결한 20초 입력에서는 최대 RSS 852.82MiB,
추론 시간 31.955초를 기록했다. 출력은 999프레임·44,955개의 유한 logits·162개 음소였다.
근거는 `mobile-runtime-capacity-report.json`이다. 이 검사는 입력 길이와 자원 사용량을
확인한 것이며 자연스러운 20초 발화의 정확도나 모바일 처리 시간을 검증한 것은 아니다.

근거 JSON과 실험 스크립트는 `.local/pronunciation-spike/`에 있다. `.local`은 Git에서 제외된다.
모델 크기·해시, 세션 수명, 반복 실행과 취소 경계의 자동 검사는 실제 마이크,
음향 정확도, iOS 메모리 한계와 별도로 평가한다.

2026-11-07 변경 후 Node 검사 407개와 Flutter 검사 304개가 통과했고,
`flutter analyze`는 문제를 보고하지 않았다. JavaScript release 웹 빌드도 성공했다.
기존 TTS 플러그인의 Wasm dry-run 경고는 남아 있으므로 이 결과를 Wasm 앱 빌드 성공으로
해석하지 않는다. 자동 검사와 로컬 빌드 결과는 공개 사이트 게시 완료를 뜻하지 않는다.

## 모델 준비와 정적 배포

저장소 루트에서 Flutter 빌드 전에 실행한다.

```powershell
python tools/pronunciation-spike/prepare-web-model.py
python tools/pronunciation-spike/prepare-web-model.py --check
cd apps/client
flutter build web --release --no-web-resources-cdn
```

`prepare-web-model.py`는 먼저 이미 배치된 조각의 개수·크기·결합 SHA-256을 확인한다.
조각이 없거나 손상됐으면 `.local/pronunciation-spike/onnx/model_quantized.extended.ort`의
고정 원본을 확인한다. 원본도 없으면 공개 사이트의 고정 조각을 받아 전체 해시를 확인한 뒤
원본을 저장하고 다시 조각으로 배치한다. `--check`는 다운로드·수정 없이 검증만 수행한다.

일반 빌드에서 ONNX→ORT 변환을 자동으로 반복하지 않는다. 재직렬화한 파일의 해시가
달라지는 경우를 관찰했으므로 검증된 고정 산출물만 사용한다. 최초 공개 게시 전에는
검증된 로컬 ORT 원본이 필요하며, 게시 후 새 환경은 공개 사이트의 고정 조각으로 복구한다.

**모델 조각은 Git에서 제외되지만 정적 배포에는 필수다.**
`apps/client/web/pronunciation/models/ko-phone-int8.ort.part00`부터 `.part21`까지
22개가 있어야 한다. 각 파일은 최대 16MiB이며 마지막 파일은 3,895,240바이트다.
Flutter 빌드 뒤 `apps/client/build/web/pronunciation/models/`에도 같은 22개가 있어야 한다.
`scripts/start-web.ps1 -Build`는 모델 준비 후 Flutter를 빌드한다.

제품 로더는 `/pronunciation/models/ko-phone-int8.ort.part00`부터 같은 사이트에서
차례로 받고 전체 해시를 검증한다. 설정·음소 사전은 고정 Hugging Face revision을 사용한다.
공개 URL을 유지한 업데이트에서도 모델 조각과 JS·WASM을 포함한 `apps/client/build/web` 전체를
함께 배포해야 한다. 배포 후에는 실제 응답의 개수·크기·결합 해시와 런타임 파일이
검증한 빌드와 일치하는지 확인해야 한다. HTTP 성공만으로 마이크 동작을 판단하지 않는다.

## 남은 실기기 확인

같은 iPhone 16 Pro Safari에서 수정 버전을 받은 상태를 확인한 뒤 최초 준비, 캐시 재사용,
마이크 허용, 짧은 녹음·20초 녹음, 분석, 재생, 취소·화면 이탈을 확인해야 한다.
재로딩이 반복되면 발생 단계와 iOS·Safari 버전, 확보 가능한 프로세스 종료 로그를 함께 기록한다.
네트워크 차단 후 로컬 분석과 음성 업로드 부재도 실제 기기에서 확인해야 한다.

현재 실측으로 확인한 것은 로컬 경로의 메모리 감소와 지정 공개 입력의 결과 일치다.
실제 Safari의 재로딩 해결, 발음 판별 정확도, Android 실행 성공은 아직 확인하지 않았다.

런타임 패치 도구는 upstream JS의 CRLF를 LF로 정규화한 뒤 원본 배포 해시를 검증한다. Windows와 LF 체크아웃의 생성 결과가 같은지 회귀 검사한다. 배포 vendor 파일은 Git 줄바꿈 변환을 막아 고정 해시를 유지한다. 모델과 런타임 동작은 이 줄바꿈 처리로 바뀌지 않는다.
