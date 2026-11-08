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
void voicemate_meter_destroy(VoiceMateNoiseMeter *meter);

#endif
