cmake_minimum_required(VERSION 3.22.1)
project(voicemate_audio C)

set(RNNOISE vendor/rnnoise)
set(FVAD vendor/libfvad)
add_library(voicemate_audio SHARED
    audio_jni.c noise_meter.c
    ${RNNOISE}/src/denoise.c
    ${RNNOISE}/src/rnn.c
    ${RNNOISE}/src/rnn_data.c
    ${RNNOISE}/src/rnn_reader.c
    ${RNNOISE}/src/pitch.c
    ${RNNOISE}/src/kiss_fft.c
    ${RNNOISE}/src/celt_lpc.c
    ${FVAD}/src/fvad.c
    ${FVAD}/src/signal_processing/division_operations.c
    ${FVAD}/src/signal_processing/energy.c
    ${FVAD}/src/signal_processing/get_scaling_square.c
    ${FVAD}/src/signal_processing/resample_48khz.c
    ${FVAD}/src/signal_processing/resample_by_2_internal.c
    ${FVAD}/src/signal_processing/resample_fractional.c
    ${FVAD}/src/signal_processing/spl_inl.c
    ${FVAD}/src/vad/vad_core.c
    ${FVAD}/src/vad/vad_filterbank.c
    ${FVAD}/src/vad/vad_gmm.c
    ${FVAD}/src/vad/vad_sp.c)
target_include_directories(voicemate_audio PRIVATE ${RNNOISE}/include ${FVAD}/include)
target_compile_features(voicemate_audio PRIVATE c_std_11)
target_compile_options(voicemate_audio PRIVATE -fvisibility=hidden)
target_link_libraries(voicemate_audio m)
