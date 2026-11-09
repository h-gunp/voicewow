#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "noise_meter.h"
#include "rnnoise.h"

static void test_processed_pcm(void) {
    VoiceMateNoiseMeter *legacy = voicemate_meter_create();
    VoiceMateNoiseMeter *practice = voicemate_meter_create();
    DenoiseState *reference = rnnoise_create(NULL);
    assert(legacy && practice && reference);
    int16_t input[480];
    float clean[480], reference_input[480], reference_output[480];
    VoiceMateAudioFrame before, after;
    int non_speech_with_audio = 0;
    for (int frame = 0; frame < 201; ++frame) {
        for (int i = 0; i < 480; ++i) {
            const int position = frame * 480 + i;
            input[i] = frame == 200 ? 0 : frame >= 100
                ? (int16_t)((int)(((uint32_t)position * 1103515245u + 12345u) >> 24) - 128)
                : (int16_t)(12000 * sin(position * .037) + 5000 * sin(position * .091));
            reference_input[i] = input[i];
            clean[i] = NAN;
        }
        rnnoise_process_frame(reference, reference_output, reference_input);
        const int old_status = voicemate_meter_process(legacy, input, &before);
        const int status = voicemate_meter_process_pcm(practice, input, &after, clean);
        assert(status == old_status && status == (frame != 0));
        if (!status) continue;
        assert(before.sequence == after.sequence && before.power == after.power);
        assert(before.clipped == after.clipped && before.rms == after.rms);
        assert(before.speech == after.speech && before.peak == after.peak);
        double energy = 0;
        for (int i = 0; i < 480; ++i) {
            assert(isfinite(clean[i]));
            assert(clean[i] == reference_output[i] / 32768.0f);
            energy += clean[i] * clean[i];
        }
        if (after.speech == 0 && energy > 0) non_speech_with_audio++;
        if (frame == 200) assert(energy > 0); /* Last real frame survives zero flush. */
    }
    assert(non_speech_with_audio > 0); /* Classification must not gate PCM. */
    assert(voicemate_meter_process_pcm(NULL, input, &after, clean) == -1);
    assert(voicemate_meter_process_pcm(practice, NULL, &after, clean) == -1);
    assert(voicemate_meter_process_pcm(practice, input, NULL, clean) == -1);
    rnnoise_destroy(reference);
    voicemate_meter_destroy(legacy);
    voicemate_meter_destroy(practice);

    practice = voicemate_meter_create();
    memset(input, 0, sizeof(input));
    assert(voicemate_meter_process_pcm(practice, input, &after, clean) == 0);
    assert(voicemate_meter_process_pcm(practice, input, &after, clean) == 1);
    for (int i = 0; i < 480; ++i) assert(clean[i] == 0);
    voicemate_meter_destroy(practice);
}

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
    test_processed_pcm();
    puts("Native noise meter: silence, delayed input, clipping, reset, PCM parity and ungated tail passed");
    return 0;
}
