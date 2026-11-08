#include "noise_meter.h"

#include <math.h>
#include <stdlib.h>
#include "rnnoise.h"
#include "fvad.h"

struct VoiceMateNoiseMeter {
    DenoiseState *noise;
    Fvad *vad;
    uint64_t sequence;
    double previous_power;
    float previous_score;
    int previous_clipped;
};

void voicemate_meter_destroy(VoiceMateNoiseMeter *meter) {
    if (!meter) return;
    if (meter->noise) rnnoise_destroy(meter->noise);
    if (meter->vad) fvad_free(meter->vad);
    free(meter);
}

VoiceMateNoiseMeter *voicemate_meter_create(void) {
    VoiceMateNoiseMeter *meter = calloc(1, sizeof(*meter));
    if (!meter) return NULL;
    meter->noise = rnnoise_create(NULL);
    meter->vad = fvad_new();
    if (!meter->noise || !meter->vad || rnnoise_get_frame_size() != 480 ||
        fvad_set_mode(meter->vad, 2) != 0 ||
        fvad_set_sample_rate(meter->vad, 48000) != 0) {
        voicemate_meter_destroy(meter);
        return NULL;
    }
    return meter;
}

int voicemate_meter_process(VoiceMateNoiseMeter *meter, const int16_t pcm[480],
                           VoiceMateAudioFrame *result) {
    if (!meter || !pcm || !result) return -1;
    float input[480], output[480];
    int16_t vad_input[480];
    double energy = 0, peak = 0, processed_energy = 0, processed_peak = 0;
    for (int i = 0; i < 480; ++i) {
        const double value = pcm[i] / 32768.0;
        input[i] = pcm[i];
        energy += value * value;
        peak = fmax(peak, fabs(value));
    }
    const float score = rnnoise_process_frame(meter->noise, output, input);
    if (!isfinite(score)) return -1;
    for (int i = 0; i < 480; ++i) {
        const double value = output[i] / 32768.0;
        if (!isfinite(value)) return -1;
        processed_energy += value * value;
        processed_peak = fmax(processed_peak, fabs(value));
        const double limited = fmax(-1.0, fmin(1.0, value));
        vad_input[i] = (int16_t)(limited * (limited < 0 ? 32768.0 : 32767.0));
    }
    const int speech = fvad_process(meter->vad, vad_input, 480);
    if (speech != 0 && speech != 1) return -1;
    const int ready = meter->sequence != 0;
    if (ready) {
        /* RNNoise output trails raw input by one frame; require both scores. */
        result->sequence = (double)(meter->sequence - 1);
        result->power = meter->previous_power;
        result->clipped = meter->previous_clipped;
        result->rms = sqrt(processed_energy / 480.0);
        result->speech = speech && score >= .5f && meter->previous_score >= .5f
            ? 1 : (!speech && score < .2f && meter->previous_score < .2f ? 0 : 2);
        result->peak = processed_peak;
    }
    meter->previous_power = energy / 480.0;
    meter->previous_clipped = peak >= .999;
    meter->previous_score = score;
    meter->sequence++;
    return ready;
}
