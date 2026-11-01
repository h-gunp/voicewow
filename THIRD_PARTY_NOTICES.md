# 제3자 참고 및 라이선스

화자 모델의 제작자, 출처, 해시, CC BY 4.0 고지와 원본 Hugging Face 메타데이터는 [MODEL-NOTICE](apps/client/web/audio/vendor/speaker/MODEL-NOTICE.txt)에 보존한다. ONNX Runtime 1.22.0의 [MIT 라이선스](apps/client/web/audio/vendor/speaker/LICENSE-ONNXRUNTIME)와 [제3자 고지](apps/client/web/audio/vendor/speaker/ONNXRUNTIME-THIRD-PARTY-NOTICES.txt)는 별도다.

실험적 VAD에는 `@ozymandiasthegreat/vad@2.0.7`의 `libfvad.wasm`을 사용한다. WebRTC/libfvad 엔진의 BSD-3-Clause LICENSE, PATENTS, AUTHORS는 별도 보존하며 버전·해시는 [자산 기록](apps/client/web/audio/vendor/libfvad/README.md)에 있다. npm 패키지 메타데이터는 MIT를 명시한다. 앱은 upstream JavaScript wrapper나 base64 decoder를 포함하지 않고 자체 wrapper로 WASM API를 직접 호출한다.

상황 선택 흐름과 하한·상한 설정은 [AppleDeveloperAcademy-MC3/Alright](https://github.com/AppleDeveloperAcademy-MC3/Alright)의 커밋 `fb3b8fc15207ab1d4f266278111065e7e2c94c5d`를 참고했다. Swift 소스와 기존 그림·폰트·로고·Lottie 자산을 제품에 복사하지 않았다. 브라우저 입력 처리와 Flutter 화면은 이 프로젝트에서 작성했다. `.reference/`는 검토용이며 앱 배포에 포함하지 않는다.

원본의 표시값은 검증된 SPL·dBA 기준이 아니다. 실제 dBFS 입력과 직접 비교하지 않는다.

## Alright 원본 LICENSE

MIT License

Copyright (c) 2024 Team. Alright

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## RNNoise 소음 억제 자산

`apps/client/web/audio/vendor/rnnoise/`에는 [Jitsi의 `@jitsi/rnnoise-wasm@0.2.1`](https://github.com/jitsi/rnnoise-wasm/tree/cb529a59a8478fe604e57986fc96afdaecfa6fb7)의 비동기 로더와 WASM을 포함한다. 패키지의 `dist/rnnoise.js`는 내용 변경 없이 `rnnoise.mjs`로 이름만 바꿨다. Jitsi 패키지 라이선스와 기존 MIT 기여 고지 원문은 [LICENSE-APACHE](apps/client/web/audio/vendor/rnnoise/LICENSE-APACHE)에 보존한다.

사용한 비동기 WASM은 RNNoise 0.1 기본 모델이다. Jitsi 0.1.0과 0.2.1 패키지의 비동기 JavaScript·WASM이 바이트 단위로 같음을 확인했고, Jitsi 0.1.0의 RNNoise 서브모듈은 커밋 `1cbdbcf1283499bbb2230a6b0f126eb9b236defd`로 고정되어 있다. 해당 소스 트리는 기본 모델 `src/rnn_data.c`를 직접 포함한다. RNNoise의 BSD 3-Clause 원문은 [LICENSE-RNNOISE](apps/client/web/audio/vendor/rnnoise/LICENSE-RNNOISE)에, 개별 소스의 저작권 고지는 [NOTICE-RNNOISE](apps/client/web/audio/vendor/rnnoise/NOTICE-RNNOISE)에 보존한다.

별도로 다운로드하는 RNNoise 0.2 모델과 Jitsi의 동기 로더는 포함하지 않는다. 정확한 패키지 출처·무결성 값·파일 해시는 [source.json](apps/client/web/audio/vendor/rnnoise/source.json)에, 모델 추적 근거와 검증 범위는 [vendor README](apps/client/web/audio/vendor/rnnoise/README.md)에 기록한다.
