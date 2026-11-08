# ONNX Runtime JNI constructs metadata/tensor classes that R8 cannot discover.
# https://onnxruntime.ai/docs/build/android.html
-keep class ai.onnxruntime.** { *; }
