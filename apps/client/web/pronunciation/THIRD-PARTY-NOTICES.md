# Local pronunciation model

The application downloads public model assets; microphone audio and recognition results are not uploaded.

- ONNX conversion: [chegrowk/ko-phone-int8](https://huggingface.co/chegrowk/ko-phone-int8/tree/dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70), revision `dbb9c196f3e5e72d41c8ce2b63e6d0c91a011b70`.
- Original model: [slplab/wav2vec2-xls-r-300m_phone-mfa_korean](https://huggingface.co/slplab/wav2vec2-xls-r-300m_phone-mfa_korean/tree/e26ff9dfb62169acf445d0060ef56863c018b20e), revision `e26ff9dfb62169acf445d0060ef56863c018b20e`.
- Both pinned model cards declare Apache-2.0. The downloaded conversion's license is included in `LICENSE-model.txt`.
- The conversion author describes ONNX opset 17 and dynamic per-channel int8 quantization of MatMul. This application uses the converted assets without modifying model weights.
- Weight file: 356,129,122 bytes; SHA-256 `c1ef511e4bac127e884edb013b16fae9e0d3d54d792039417aa3cf4b48e8a134`. Configuration and vocabulary hashes are fixed in `phone-engine.mjs`.
- ONNX Runtime Web is reused from `../prosody/vendor/onnx/`; its existing license and third-party notices remain there.

Original-work citation from the conversion card: Yeo, E., Ryu, H., Lee, J., Kim, S., & Chung, M. (2023). Comparison of L2 Korean pronunciation error patterns from five L1 backgrounds by using automatic phonetic transcription. Proceedings of the 20th International Congress of Phonetic Sciences, pp. 2696–2700.

The original model's reported metric is not VoiceMate accuracy. Browser/device performance and pronunciation accuracy require separate validation.
