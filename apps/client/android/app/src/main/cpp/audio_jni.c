#include <jni.h>
#include <stdint.h>
#include "noise_meter.h"

static void fail(JNIEnv *env, const char *type, const char *message) {
    jclass error = (*env)->FindClass(env, type);
    if (error) (*env)->ThrowNew(env, error, message);
}

JNIEXPORT jlong JNICALL
Java_com_voicewow_voicemate_NativeNoiseMeter_create(JNIEnv *env, jobject object) {
    (void)object;
    VoiceMateNoiseMeter *meter = voicemate_meter_create();
    if (!meter) fail(env, "java/lang/IllegalStateException", "Audio analysis initialization failed");
    return (jlong)(intptr_t)meter;
}

JNIEXPORT jdoubleArray JNICALL
Java_com_voicewow_voicemate_NativeNoiseMeter_process(JNIEnv *env, jobject object,
                                                  jlong handle, jshortArray pcm) {
    (void)object;
    if (!handle || !pcm || (*env)->GetArrayLength(env, pcm) != 480) {
        fail(env, "java/lang/IllegalArgumentException", "Audio analysis requires 480 PCM16 samples");
        return NULL;
    }
    jshort samples[480];
    (*env)->GetShortArrayRegion(env, pcm, 0, 480, samples);
    if ((*env)->ExceptionCheck(env)) return NULL;
    VoiceMateAudioFrame frame;
    const int status = voicemate_meter_process((VoiceMateNoiseMeter *)(intptr_t)handle,
                                               samples, &frame);
    if (status < 0) {
        fail(env, "java/lang/IllegalStateException", "Audio analysis failed");
        return NULL;
    }
    jdoubleArray result = (*env)->NewDoubleArray(env, status ? 6 : 0);
    if (result && status) {
        const jdouble values[] = {frame.sequence, frame.power, frame.clipped,
                                  frame.rms, frame.speech, frame.peak};
        (*env)->SetDoubleArrayRegion(env, result, 0, 6, values);
    }
    return result;
}

JNIEXPORT void JNICALL
Java_com_voicewow_voicemate_NativeNoiseMeter_destroy(JNIEnv *env, jobject object,
                                                  jlong handle) {
    (void)env;
    (void)object;
    voicemate_meter_destroy((VoiceMateNoiseMeter *)(intptr_t)handle);
}

JNIEXPORT jlong JNICALL
Java_com_voicewow_voicemate_NativePracticeAudio_create(JNIEnv *env, jobject object,
                                                    jboolean noise_reduction_enabled) {
    (void)object;
    VoiceMateNoiseMeter *meter = voicemate_meter_create_with_noise_reduction(noise_reduction_enabled == JNI_TRUE);
    if (!meter) fail(env, "java/lang/IllegalStateException", "Practice audio initialization failed");
    return (jlong)(intptr_t)meter;
}

JNIEXPORT jfloatArray JNICALL
Java_com_voicewow_voicemate_NativePracticeAudio_process(JNIEnv *env, jobject object,
                                                     jlong handle, jshortArray pcm) {
    (void)object;
    if (!handle || !pcm || (*env)->GetArrayLength(env, pcm) != 480) {
        fail(env, "java/lang/IllegalArgumentException", "Practice audio requires 480 PCM16 samples");
        return NULL;
    }
    jshort samples[480];
    (*env)->GetShortArrayRegion(env, pcm, 0, 480, samples);
    if ((*env)->ExceptionCheck(env)) return NULL;
    VoiceMateAudioFrame frame;
    jfloat values[481];
    const int status = voicemate_meter_process_pcm((VoiceMateNoiseMeter *)(intptr_t)handle,
                                                   samples, &frame, values + 1);
    if (status < 0) {
        fail(env, "java/lang/IllegalStateException", "Practice audio processing failed");
        return NULL;
    }
    jfloatArray result = (*env)->NewFloatArray(env, status ? 481 : 0);
    if (result && status) {
        values[0] = (jfloat)frame.speech;
        (*env)->SetFloatArrayRegion(env, result, 0, 481, values);
    }
    return result;
}

JNIEXPORT void JNICALL
Java_com_voicewow_voicemate_NativePracticeAudio_destroy(JNIEnv *env, jobject object,
                                                     jlong handle) {
    Java_com_voicewow_voicemate_NativeNoiseMeter_destroy(env, object, handle);
}
