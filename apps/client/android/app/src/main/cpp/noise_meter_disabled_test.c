#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "noise_meter.h"
#include "rnnoise.h"
#include "fvad.h"

/* Link this test with noise_meter.c only: any model allocation or call is a failure. */
static int model_calls;
DenoiseState *rnnoise_create(RNNModel *model) { (void)model; model_calls++; return NULL; }
void rnnoise_destroy(DenoiseState *state) { (void)state; model_calls++; }
int rnnoise_get_frame_size(void) { model_calls++; return 480; }
float rnnoise_process_frame(DenoiseState *state, float *out, const float *in) {
    (void)state; (void)out; (void)in; model_calls++; return NAN;
}
Fvad *fvad_new(void) { model_calls++; return NULL; }
void fvad_free(Fvad *vad) { (void)vad; model_calls++; }
int fvad_set_mode(Fvad *vad, int mode) { (void)vad; (void)mode; model_calls++; return -1; }
int fvad_set_sample_rate(Fvad *vad, int rate) { (void)vad; (void)rate; model_calls++; return -1; }
int fvad_process(Fvad *vad, const int16_t *pcm, size_t length) {
    (void)vad; (void)pcm; (void)length; model_calls++; return -1;
}

int main(void) {
    assert(voicemate_meter_create_with_processing(0, -1) == NULL);
    VoiceMateNoiseMeter *meter = voicemate_meter_create_with_processing(0, 0);
    assert(meter && model_calls == 0);
    int16_t pcm[480];
    float output[480];
    VoiceMateAudioFrame frame;
    for (int sequence = 0; sequence < 20; sequence++) {
        for (int i = 0; i < 480; i++) pcm[i] = sequence % 2 ? (int16_t)(i * 119 - 28000) : 0;
        assert(voicemate_meter_process_pcm(meter, pcm, &frame, output) == 1);
        assert(frame.sequence == sequence && frame.speech == -1);
        for (int i = 0; i < 480; i++) assert(output[i] == pcm[i] / 32768.0f);
        assert(model_calls == 0);
    }
    voicemate_meter_destroy(meter);
    assert(model_calls == 0);
    puts("Disabled processing: zero RNNoise/libfvad calls, exact raw PCM and disabled VAD marker passed");
    return 0;
}
