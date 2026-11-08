#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "noise_meter.h"

int main(void) {
    VoiceMateNoiseMeter *meter = voicemate_meter_create();
    assert(meter);
    VoiceMateAudioFrame frame;
    int16_t samples[480] = {0};
    assert(voicemate_meter_process(meter, samples, &frame) == 0);
    for (int i = 0; i < 100; ++i) {
        assert(voicemate_meter_process(meter, samples, &frame) == 1);
        assert(frame.sequence == i);
        assert(frame.power == 0 && frame.clipped == 0);
        assert(frame.rms == 0 && frame.peak == 0 && frame.speech == 0);
    }
    for (int i = 0; i < 480; ++i) samples[i] = 32767;
    assert(voicemate_meter_process(meter, samples, &frame) == 1);
    assert(frame.power == 0 && frame.clipped == 0);
    memset(samples, 0, sizeof(samples));
    assert(voicemate_meter_process(meter, samples, &frame) == 1);
    assert(fabs(frame.power - pow(32767.0 / 32768.0, 2)) < 1e-12);
    assert(frame.clipped == 1 && isfinite(frame.rms) && isfinite(frame.peak));
    voicemate_meter_destroy(meter);

    meter = voicemate_meter_create();
    assert(meter);
    assert(voicemate_meter_process(meter, samples, &frame) == 0);
    assert(voicemate_meter_process(meter, samples, &frame) == 1);
    assert(frame.sequence == 0 && frame.power == 0 && frame.speech == 0);
    assert(voicemate_meter_process(NULL, samples, &frame) == -1);
    voicemate_meter_destroy(meter);
    voicemate_meter_destroy(NULL);
    puts("Native noise meter: silence, delayed input, clipping, reset passed");
    return 0;
}
