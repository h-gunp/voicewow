# 발음·높낮이 녹음의 소음 억제와 발화 구분

2026-11-10 변경이다. 기존 RNNoise와 libfvad를 두 훈련의 녹음에도 적용한다. 발음 모델은 `icig/normal-korean-ipa-translation`의 기존 고정 revision을 유지한다.

| 경로 | 처리와 사용처 |
| --- | --- |
| 웹 | 48kHz AudioWorklet → RNNoise·libfvad → 연속 PCM. 발음 모델 입력은 16kHz로 변환한다. 높낮이 실시간 그래프·최종 분석·재생·선택적 대본 위치 인식은 같은 정제 PCM을 사용한다. |
| Android | record 플러그인의 48kHz PCM16 → 직렬 네이티브 RNNoise·libfvad → 지연 보상 FIR 16kHz. 공유 DeviceAudioService가 라이브 분석·WAV·발음 모델에 같은 결과를 전달한다. |

발화 판정은 발화·비발화·불확실을 구분한다. 발음 화면은 판정에 따라 말소리 감지·대기 상태를 표시한다. 높낮이는 확정 비발화 구간을 피치 계산에서 제외한다. 불확실 구간은 기존 음향 분석으로 판단한다. 웹은 100ms 청크의 판정 요약을 사용하고 Android는 10ms 판정을 분석 창에 대응시킨다.

VAD만으로 녹음 샘플을 삭제하거나 구간을 이어 붙이지 않는다. 말 사이의 쉼과 약한 자음, 원래 녹음 길이를 유지한다. 무음 오류에는 원신호의 분산 조건도 함께 사용한다. 소음 억제와 리샘플링이 만드는 full-scale 초과 출력은 정규 PCM 범위로 제한한다.

RNNoise의 첫 지연 프레임은 출력하지 않고, 종료 시 마지막 프레임과 부분 프레임을 처리한 뒤 최종 PCM을 확정한다. 정상 종료는 처리 중인 PCM을 기다리며 취소는 이전 세대의 늦은 응답을 폐기한다. 웹 대본 인식에는 복사본을 전달해 worker의 buffer transfer가 녹음·그래프용 PCM을 무효화하지 않게 한다.

음량 측정 경로와 보정값은 유지한다. 추가 모델 다운로드나 음성 서버 전송은 없다. 예시 음성과 사용자가 불러온 파일에는 이 마이크 전처리를 소급 적용하지 않는다.

검사는 `tests/audio/processed-*.test.mjs`, 발음 recorder/session 검사, 웹 prosody 검사, Flutter device_audio_processing·practice_session·발음 UI 검사, Kotlin PracticeAudioProcessorTest와 C noise_meter_test가 담당한다. 연결된 Galaxy Jump2에서는 C 처리 검사를 직접 실행해 종료 샘플 보존과 기존 volume 지표 동등성을 확인했다. 이 실행은 마이크 음질이나 실제 발음 정확도 평가가 아니다.
