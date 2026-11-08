# Android volume processing

`noise_meter.c` keeps the web pipeline's 48 kHz, 480-sample framing,
RNNoise one-frame alignment, adjacent model score checks and libfvad mode 2.
`audio_jni.c` exposes it to the Android capture thread. Each capture owns one
handle; the capture thread must finish before that handle is destroyed.

`vendor/source.json` pins every unchanged source file by upstream commit and
SHA-256. RNNoise uses the same model source revision recorded by the web engine.
libfvad sources come from the immutable wrapper revision associated with the
web WASM artifact. Native compilation is a new build, not a claim of binary
identity with WASM. Upstream copyright, license and patent notices remain in
each vendor directory.

`noise_meter_test.c` is a host-side check of silence, delayed raw-frame
alignment, clipping and a fresh capture. It is excluded from the Android
shared library. Compile it with `noise_meter.c`, the vendor C sources listed
in `CMakeLists.txt`, both vendor include directories and the math library.
