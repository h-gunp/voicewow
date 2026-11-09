#ifndef VOICEMATE_NOISE_METER_H
#define VOICEMATE_NOISE_METER_H

#include <stdint.h>

typedef struct VoiceMateNoiseMeter VoiceMateNoiseMeter;

typedef struct {
    double sequence, power, clipped, rms, speech, peak;
} VoiceMateAudioFrame;

VoiceMateNoiseMeter *voicemate_meter_create(void);
/* Returns 0 while priming, 1 for an aligned frame, and -1 on engine failure. */
int voicemate_meter_process(VoiceMateNoiseMeter *meter, const int16_t pcm[480],
                           VoiceMateAudioFrame *result);
/* Same aligned metrics, plus normalized RNNoise PCM when ready; never VAD-gated.
 * clean may be NULL. The caller owns partial-frame padding and final zero flush. */
int voicemate_meter_process_pcm(VoiceMateNoiseMeter *meter, const int16_t pcm[480],
                               VoiceMateAudioFrame *result, float clean[480]);
void voicemate_meter_destroy(VoiceMateNoiseMeter *meter);

#endif
