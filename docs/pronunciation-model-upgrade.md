# 한국어 발음 모델 교체 — 2026-11-09

현재 모델은 `icig/normal-korean-ipa-translation`의 고정 revision `772950d64427910937e11c5b76c9e4594059ce8c`다. 기존 MFA XLS-R 315M 모델에서 한국어 IPA Wav2Vec2 94.4M 모델로 교체했다. 모델 크기가 아니라 동일한 실제 발화의 음소 오류 수로 선택했다.

## 비교 방법과 결과

[Seoul Corpus / OpenSLR 113](https://www.openslr.org/113/)의 사람이 수정한 음소 전사를 사용했다. 18개는 원본 음성에서, 추가 12개는 [KRAFTON/KMMAU](https://huggingface.co/datasets/KRAFTON/KMMAU)의 같은 말뭉치 발췌 음성에서 가져왔다. 추가 표본은 공식 TextGrid의 구간과 대조했지만 원본 FLAC 바이트와는 대조하지 않았다. 녹음은 합계 약 62.4초이며 모델 출력을 보기 전에 선택했다.

서로 다른 음소 사전을 말뭉치가 구별하는 공통 자모로 변환했다. 초성/종성 표기, 유무성 변이, ㄹ 표기, 말뭉치가 합친 모음 구별은 양쪽에 같은 규칙을 적용했다. 구분자만 제거하고 미매핑 음소는 오류로 남겼다. 따라서 아래 수치는 **공통 음소 오류율**이며, 모든 발음 구별을 평가하는 수치는 아니다.

| 모델·입력 | 원본 18개 / 451음소 | 확장 12개 / 367음소 | 전체 / 818음소 |
|---|---:|---:|---:|
| 기존 int8, 기존 제품 전처리 | 124 | 91 | 215 (26.28%) |
| 기존 int8, 원래 HF 전처리 | 130 | 93 | 223 (27.26%) |
| 새 IPA FP32, 공식 전처리 | 94 | 61 | 155 (18.95%) |
| 새 IPA int8 비교 실험 | 96 | 64 | 160 (19.56%) |

새 FP32 모델은 이 표본에서 오류가 60개 줄었다. 작은 편의 표본이며 학습 자료 중복 여부는 알 수 없다. 사용자의 실제 발음, 청각장애·발음장애 음성, 휴대폰 마이크 녹음의 정확도를 측정한 결과로 확대하지 않는다. 원본 음성·사용자 녹음은 GitHub나 Sites에 올리지 않았다. 원본 말뭉치는 CC BY-NC 2.0, 추가 발췌 데이터는 CC BY-NC-SA 4.0이며 데이터 자체는 이 저장소에 포함하지 않는다.

## 제품 변경

- 모델이 요구하는 raw 16kHz PCM을 유지한다. 이전 정규화와 400ms 앞뒤 패딩을 제거하되 잘못된 입력·무음 검증은 유지한다.
- 55개 CTC 클래스 중 blank 0과 공백 51만 제외한다. 특수·알 수 없는 토큰은 불확실로 표시한다.
- IPA 유무성 변이를 한국어 음소에 대응시키고, 관측된 다음 모음만 사용해 초성·종성을 배치한다. 기준 문장으로 인식 결과를 고치지 않는다. 된소리·거센소리 차이와 회색 불확실 표시를 유지한다.
- 새 모델의 명시적인 `wʌ`를 `ㅝ`로 처리한다. 과거 MFA의 모호한 `uEO` 결과는 그대로 보류한다.
- 원본 safetensors 377,681,876바이트는 고정 Hugging Face 주소에서 직접 받는다. 282,052바이트 ONNX graph만 저장소에 포함한다. 학습 initializer 212개 모두 원본 파일의 정확한 바이트 범위를 참조하며 내장 학습 가중치는 0바이트다.
- Android graph URL은 모델 자산 커밋 `4972547545da42780de509218990714eb7a12f7a`로 고정했다. 모든 다운로드의 크기·SHA-256과 새 캐시 revision을 검사한다.
- 웹 세션은 graph 최적화를 끈다. 브라우저 녹음은 최대 10초, Android는 최대 20초다. 이전 모델의 공개 조각 파일은 새 다운로드 경로에서 사용하지 않는다.

상세 출처·텐서 offset·해시는 [source.json](../apps/client/web/pronunciation/models/source.json)에 있다. 원본 저장소의 라이선스는 명시되지 않았으며 기존 Apache-2.0 모델의 고지와 구분했다.

## 실행한 검사

- Python ONNX Runtime 1.31.1: 외부 참조 graph의 실제 발화 30개 출력이 원본 PyTorch와 모두 일치했다.
- 제품 ORT Web 1.23.2 엔진: 모델 파일 검증부터 실제 추론까지 실행했고 30개 출력이 native/Torch와 모두 일치했다. 오류율 155/818을 유지했다.
- Node WASM 최대 RSS: 짧은 발화 30개 822.58MiB, 별도 10초 합성 입력 920.24MiB, 20초 합성 입력 1,104~1,109MiB였다. 이 결과로 웹 녹음 상한을 10초로 정했다. 실제 Safari의 메모리 측정은 아니다.
- JS/Dart IPA 매핑은 55개 토큰을 고립·다음 모음 문맥의 110개 경우로 대조했다. 같은 결과를 반환했다.
- Node 회귀 검사, Flutter 검사·정적 분석, Android JUnit 검사와 release APK·JS 웹 빌드를 실행했다. 최종 배포·설치 영수증은 작업 공간의 `.local/ipa-deployment-receipt.json`에 기록한다.

현재 모델 준비와 재현은 `python tools/pronunciation-spike/prepare-ipa-model.py`다. 외부 참조 graph 재생성은 `tools/pronunciation-spike/export-ipa-model.py`의 고정 도구 버전으로 수행한다. 로컬 평가 상세 근거는 `.local/model-candidates/`, `.local/model-parity-audit/seoul30-mfa/`, `.local/pronunciation-benchmark-sources/`에 보관했다.
