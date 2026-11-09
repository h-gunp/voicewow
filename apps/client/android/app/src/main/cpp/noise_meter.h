#ifndef VOICEMATE_NOISE_METER_H
#define VOICEMATE_NOISE_METER_H

#include <stdint.h>

typedef struct VoiceMateNoiseMeter VoiceMateNoiseMeter;

typedef struct {
    double sequence, power, clipped, rms, speech, peak;
} VoiceMateAudioFrame;

VoiceMateNoiseMeter *voicemate_meter_create(void);
VoiceMateNoiseMeter *voicemate_meter_create_with_noise_reduction(int enabled);
/* Returns 0 while RNNoise primes, 1 for an aligned frame, and -1 on failure.
 * Noise-reduction-disabled capture returns the current frame immediately. */
int voicemate_meter_process(VoiceMateNoiseMeter *meter, const int16_t pcm[480],
                           VoiceMateAudioFrame *result);
/* Same aligned metrics and normalized PCM; never VAD-gated. With noise reduction
 * disabled PCM is unchanged. clean may be NULL; the caller owns partial padding. */
int voicemate_meter_process_pcm(VoiceMateNoiseMeter *meter, const int16_t pcm[480],
                               VoiceMateAudioFrame *result, float clean[480]);
void voicemate_meter_destroy(VoiceMateNoiseMeter *meter);

#endif
