# 발음 입력 안정화 — 2026-11-09

Android와 웹은 같은 고정 음소 모델을 기기 안에서 실행한다. 이번 변경은 녹음의 대기 시간과 크기에 따라 입력이 달라지는 부분, 정상 복수 발음의 비교 누락을 수정한다. 선택 문장을 인식기에 넣거나 관측 음소를 정답으로 바꾸지 않는다.

## 변경

- 원본 PCM의 형식·범위·길이·분산을 먼저 검사한다.
- 최대 진폭의 1%와 0.0001 중 큰 값으로 첫·마지막 유효 샘플을 찾는다. 그 앞뒤 400ms를 보존하고 녹음 바깥은 0으로 채운다. 내부 쉼과 여유 구간 안의 약한 소리는 보존한다.
- 샘플 단위 경계를 사용한다. 10ms 프레임 단위로 자르면 버튼 시점에 따라 모델 입력의 위상이 달라졌다.
- 결과가 20초를 넘거나 경계가 없으면 원본 길이를 유지한다.
- 분산이 양수임을 확인한 뒤 제곱근으로 정규화한다. 기존의 분모 `sqrt(variance + 1e-7)`은 작은 소리를 상대적으로 더 작게 만들었다.
- `맛있-`, `멋있-`이 원문에 있을 때만 허용된 두 표준 발음을 비교 후보에 추가한다. 실제 인식 결과와 회색 불확실 표시는 유지한다. 근거는 [국립국어원 답변](https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?qna_seq=324749)과 `pronunciation_references_test.dart`에 있다.

모델·다운로드 크기·디코더는 유지한다. CTC beam 4/8/16도 비교했지만, 기존 입력의 20개 결과가 greedy와 같아 이번에는 추가하지 않았다.

## 측정 범위

공개 한국어 읽기 음성 2개와 저장소의 합성 가이드 3개를 사용했다. 공개 원본은 [고정 Hugging Face revision](https://huggingface.co/k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16/tree/ba6078bca4daf3f0dd37f79d0ab505af71df14a6/test_wavs)의 `0.wav`, `2.wav`다. 24kHz 합성 가이드는 비교 실험에서만 동일한 선형 보간으로 16kHz로 바꿨다.

각 표본의 원본과 0.15배 음량을 실제 ONNX 모델에 넣었다. 최종 후보 10회 추론에서 5쌍의 음소 출력이 모두 같았다. 기존 전처리에서는 5쌍 중 4쌍이 같았다. 별도의 패딩 10조건과 임의 길이 패딩 30조건은 모델 입력 배열·해시의 동일성을 검사했으며, 추가 추론으로 계산하지 않는다.

| 표본 | 기존 원본 대비 최종 원본의 음소 편집거리 | 최종 원본과 작은 음량의 차이 |
| --- | ---: | ---: |
| 공개 음성 0 | 0 | 0 |
| 공개 음성 2 | 0 | 0 |
| 합성 hello | 1 | 0 |
| 합성 phrase | 8 | 0 |
| 합성 sunglasses | 0 | 0 |

합성 hello에는 `L` 하나가 추가됐고 phrase의 출력도 달라졌다. 사람이 검수한 음소 정답이 없으므로 이 변화를 정확도 개선 수치로 계산하지 않는다. 이번 측정은 음량·버튼 대기에 대한 결과 일관성을 확인한 것이다. 실제 사용자 반복 발화·주변 잡음·여러 기종의 정확도 평가는 별도다.

모델 SHA-256은 `c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134`다. ONNX Runtime 1.31.0 CPU 단일 스레드로 측정했다. [기록](pronunciation-input-stability-results.json)에 원본·입력·logits 해시와 실제 추론/입력 동일성 검사를 구분했다.

추가로 제품 웹 ORT 엔진을 Node WASM에서 직접 실행했다. 공개 음성 0의 원본과 0.15배 음량+16,159샘플 앞 무음+32,000샘플 뒤 무음이 같은 음소를 반환했고, 기존 원본 결과도 유지했다. 이는 브라우저 마이크 검사가 아니다.

## 회귀 검사

`tools/pronunciation-spike/phones.test.mjs`와 Android `PronunciationPcmTest`는 원본 불변성, 16,001/16,080/16,159샘플 앞 무음, 음량 차이, 약한 앞뒤 소리, 내부 쉼, 20초 상한, 잘못된 입력을 검사한다. Python 후보와 제품 웹의 10개 정규화 배열은 Float32 값까지 같았다.

```powershell
node --test tools/pronunciation-spike/*.test.mjs tools/prosody-web-tests/*.test.mjs
node --test tests/audio/*.test.mjs tools/asr-spike/*.test.mjs
# apps/client
flutter test --no-pub
# apps/client/android
.\gradlew.bat :app:testDebugUnitTest --console=plain
```

이번 배포에는 앞선 Android 마이크 연결, 표시 오프셋 105, ONNX JNI 클래스의 R8 보존, 중단된 모델 다운로드 임시 파일 정리, TTS 실패 복구도 함께 포함한다. 웹의 기존 표시 오프셋 114는 유지한다.
