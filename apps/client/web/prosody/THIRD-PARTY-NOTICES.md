# VoiceMate AI 읽기 예시의 공개 소프트웨어 및 모델

이 기능은 입력한 문장을 읽는 AI 예시 음성을 만듭니다. 예시의 음높이·강약을 실제 음성에서 추출하며, 예시 자체가 유일한 정답이나 검증된 자연스러움 평가 기준이라는 뜻은 아닙니다. 진단·치료 판단 또는 의학적 결과 해석을 제공하지 않습니다.

## Supertonic 3

- 개발사: Supertone Inc.
- 소스: https://github.com/supertone-oss-archive/supertonic
- 소스 고정 버전: `1e9799e964ea4c0dad7cde993b65c3c813a7b373`
- 모델: https://huggingface.co/supertone-oss-archive/supertonic-3
- 모델 고정 버전: `aafc6e32416a594460b32413efc49d7fe4ce6d46`
- 코드 라이선스: [MIT 전문](./vendor/supertonic/LICENSE-code.txt)
- 모델 라이선스: [BigScience Open RAIL-M 전문 및 이용 제한](./vendor/supertonic/LICENSE-model.txt)

VoiceMate에서 제공하는 모델 이용 및 배포에는 위 Open RAIL-M 라이선스가 적용됩니다. 모델을 이용하는 사용자는 해당 라이선스의 5항 및 첨부 A에 명시된 이용 제한을 준수해야 합니다. 전체 이용 조건은 링크한 전문을 확인할 수 있습니다. 모델 및 코드의 저작권과 고지 사항은 원저작자에게 귀속됩니다.

포함한 `vendor/supertonic/helper.js`는 공식 웹 예제입니다. VoiceMate에서는 모듈 가져오기 경로만 같은 사이트의 고정 버전 ONNX Runtime으로 변경했습니다. `engine.js`, `tts-client.js`, `tts-worker.js`는 VoiceMate의 연결 코드이며 원개발사의 공식 제품이나 승인 표시가 아닙니다. 원본 저장소는 보관 상태이며 업데이트나 지원을 제공하지 않습니다.

한국어 `ko`, 기본 음성 `F3`, 생성 단계 8, 속도 1.0을 사용합니다. 문장마다 실제 합성 음성을 생성하므로 생성된 읽기 방식은 달라질 수 있습니다. 연습 중에는 생성된 예시를 유지합니다. 단어별 시간표나 한국어 억양의 정답 표시는 생성하지 않습니다.

모델과 설정·기본 음성 파일은 처음 사용할 때 약 399MB를 Hugging Face의 위 고정 버전에서 내려받습니다. 파일은 이 브라우저의 모델 캐시에 보관될 수 있습니다. 모델 다운로드 요청에 대본이나 사용자 녹음을 포함하지 않습니다. 문장과 생성된 음성은 기기 안에서 처리합니다.

## ONNX Runtime Web

- 개발사: Microsoft Corporation
- 버전: **1.23.2**
- 소스: https://github.com/microsoft/onnxruntime/tree/v1.23.2
- 라이선스: [MIT 전문](./vendor/onnx/LICENSE.txt)
- 구성 요소 고지: [제3자 저작권 안내](./vendor/onnx/ThirdPartyNotices.txt)

공식 npm 패키지 `onnxruntime-web@1.23.2`의 `ort.wasm.min.mjs`, `ort-wasm-simd-threaded.mjs`, `ort-wasm-simd-threaded.wasm`을 수정 없이 함께 제공합니다. 실행 코드와 WebAssembly 파일은 같은 버전입니다. 별도 작업 스레드에서 단일 스레드 WebAssembly를 사용합니다.

## 검증 범위

공개 모델과 동일한 WebAssembly 실행 파일을 사용한 Node 환경의 음성 생성 점검은 브라우저·아이폰 실기기 검증과 다릅니다. 음성 생성 가능 여부는 말하기 평가의 정확도나 임상적 효과를 입증하지 않습니다.
