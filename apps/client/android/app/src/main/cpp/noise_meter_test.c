#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include "noise_meter.h"
#include "rnnoise.h"
#include "fvad.h"

static void test_raw_pronunciation_pcm(void) {
    assert(voicemate_meter_create_with_noise_reduction(-1) == NULL);
    VoiceMateNoiseMeter *meter = voicemate_meter_create_with_noise_reduction(0);
    Fvad *reference = fvad_new();
    assert(meter && reference);
    assert(fvad_set_mode(reference, 2) == 0);
    assert(fvad_set_sample_rate(reference, 48000) == 0);
    int16_t pcm[480] = {0};
    float output[480];
    VoiceMateAudioFrame frame;
    int non_speech_with_audio = 0;
    for (int sequence = 0; sequence < 201; ++sequence) {
        for (int i = 0; i < 480; ++i) {
            const int position = sequence * 480 + i;
            pcm[i] = sequence == 0 ? 0 : sequence > 100
                ? (int16_t)((int)(((uint32_t)position * 1103515245u + 12345u) >> 24) - 128)
                : (int16_t)(12000 * sin(position * .037) + 5000 * sin(position * .091));
        }
        const int expected_speech = fvad_process(reference, pcm, 480);
        assert(voicemate_meter_process_pcm(meter, pcm, &frame, output) == 1);
        assert(frame.sequence == sequence && frame.speech == expected_speech);
        double energy = 0, peak = 0;
        for (int i = 0; i < 480; ++i) {
            assert(output[i] == pcm[i] / 32768.0f);
            const double value = pcm[i] / 32768.0;
            energy += value * value;
            peak = fmax(peak, fabs(value));
        }
        assert(fabs(frame.power - energy / 480.0) < 1e-14);
        assert(fabs(frame.rms - sqrt(energy / 480.0)) < 1e-12);
        assert(frame.peak == peak && frame.clipped == (peak >= .999));
        if (frame.speech == 0 && energy > 0) non_speech_with_audio++;
    }
    assert(non_speech_with_audio > 0);
    for (int i = 0; i < 480; ++i) pcm[i] = i % 2 ? -32768 : 32767;
    assert(voicemate_meter_process_pcm(meter, pcm, &frame, output) == 1);
    assert(frame.sequence == 201 && frame.clipped == 1 && frame.peak == 1);
    for (int i = 0; i < 480; ++i) assert(output[i] == pcm[i] / 32768.0f);
    assert(voicemate_meter_process_pcm(NULL, pcm, &frame, output) == -1);
    assert(voicemate_meter_process_pcm(meter, NULL, &frame, output) == -1);
    assert(voicemate_meter_process_pcm(meter, pcm, NULL, output) == -1);
    assert(voicemate_meter_process_pcm(meter, pcm, &frame, NULL) == 1);
    voicemate_meter_destroy(meter);
    fvad_free(reference);
}

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
    test_raw_pronunciation_pcm();
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
    puts("Native audio: raw pronunciation PCM/VAD parity and default RNNoise delay, clipping, reset and ungated tail passed");
    return 0;
}
