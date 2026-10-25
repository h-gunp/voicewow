# RNNoise 배포 자산과 출처

이 디렉터리는 `@jitsi/rnnoise-wasm@0.2.1`의 **비동기 로더와 RNNoise 0.1 기본 모델**을 보존한다. 패키지의 `dist/rnnoise.js`를 내용 변경 없이 `rnnoise.mjs`로 이름만 바꾸고, `dist/rnnoise.wasm`을 함께 복사했다. 네트워크에서 모델을 추가로 내려받거나 다시 학습하지 않는다.

## 포함한 파일

| 파일 | 출처와 역할 |
|---|---|
| `rnnoise.mjs` | npm 패키지의 `dist/rnnoise.js` 원문인 비동기 Emscripten 로더다. |
| `rnnoise.wasm` | npm 패키지의 `dist/rnnoise.wasm` 원문이며 기본 모델을 포함한다. |
| `LICENSE-APACHE` | npm 패키지의 `LICENSE` 원문이다. 끝부분의 기존 MIT 기여 고지도 그대로 보존한다. |
| `LICENSE-RNNOISE` | 아래에 고정한 RNNoise 소스 커밋의 `COPYING` 원문인 BSD 3-Clause 라이선스다. |
| `NOTICE-RNNOISE` | 같은 RNNoise 커밋의 `src/`와 `include/`에서 추출한 개별 파일의 저작권·라이선스 주석이다. 원문의 파일별 고지를 보존한다. |
| `source.json` | 패키지 버전, 다운로드 주소, 무결성 값, 파일 해시와 소스 추적 근거를 기록한다. |

## 기본 모델의 추적 근거

1. [Jitsi 패키지의 고정 커밋 README](https://github.com/jitsi/rnnoise-wasm/blob/cb529a59a8478fe604e57986fc96afdaecfa6fb7/README.md)는 비동기 `rnnoise.wasm`이 RNNoise 0.1이고 동기 버전은 RNNoise 0.2라고 설명한다. 여기에는 동기 버전 `rnnoise-sync.js`를 포함하지 않는다.
2. [npm 0.1.0 패키지](https://registry.npmjs.org/@jitsi/rnnoise-wasm/0.1.0)와 0.2.1 패키지의 비동기 JavaScript·WASM을 비교해 두 파일 모두 바이트가 일치함을 확인했다.
3. Jitsi 0.1.0의 커밋 `cf998963932adc1dc9d060d42aaa1efe622d1318`은 RNNoise 서브모듈을 [`1cbdbcf1283499bbb2230a6b0f126eb9b236defd`](https://github.com/xiph/rnnoise/tree/1cbdbcf1283499bbb2230a6b0f126eb9b236defd)로 고정한다.
4. 해당 RNNoise 소스 트리에는 기본 가중치인 [`src/rnn_data.c`](https://github.com/xiph/rnnoise/blob/1cbdbcf1283499bbb2230a6b0f126eb9b236defd/src/rnn_data.c)가 직접 포함된다. 같은 트리의 [`COPYING`](https://github.com/xiph/rnnoise/blob/1cbdbcf1283499bbb2230a6b0f126eb9b236defd/COPYING)을 재배포 고지로 보존한다. 별도로 다운로드하는 RNNoise 0.2 모델 archive는 사용하지 않는다.

패키지의 무결성 값과 원본 파일 해시는 확인했다. 배포된 WASM을 원본 C 코드로 다시 빌드해 재현하는 검증은 수행하지 않았다. 음량 보존, 실제 사용자 발화, 모바일 처리 성능은 이 자산의 라이선스·출처 확인과 별도로 검증할 항목이다.

패키지를 갱신할 때는 비동기 파일의 모델 버전과 소스 추적 근거를 다시 확인하고 `source.json` 및 고지를 함께 갱신한다. 로더를 수정하면 원본 해시와 수정 후 해시를 구분하고 수정 내용을 기록한다.
