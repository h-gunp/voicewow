// The pinned libfvad build accepts 48 kHz and performs its own downsampling.
export async function createVoiceActivity(binary) {
  const {instance} = await WebAssembly.instantiate(binary);
  const api = instance.exports;
  api._initialize();
  const handle = api.fvad_new();
  if (!handle) throw new Error('VAD allocation failed');
  let ptr = 0;
  try {
    if (api.fvad_set_mode(handle, 0) !== 0 || api.fvad_set_sample_rate(handle, 48000) !== 0) throw new Error('VAD setup failed');
    ptr = api.malloc(480 * 2);
    if (!ptr) throw new Error('VAD allocation failed');
  } catch (error) {
    api.fvad_free(handle);
    throw error;
  }
  let disposed = false;
  return {
    process(frame) {
      if (disposed) throw new Error('VAD disposed');
      if (frame.length !== 480) throw new RangeError('VAD needs a 480 sample frame');
      const pcm = new Int16Array(api.memory.buffer, ptr, 480);
      for (let i = 0; i < 480; i++) {
        if (!Number.isFinite(frame[i])) throw new RangeError('Samples must be finite');
        const sample = Math.max(-1, Math.min(1, frame[i]));
        pcm[i] = sample < 0 ? sample * 32768 : sample * 32767;
      }
      const result = api.fvad_process(handle, ptr, 480);
      if (result !== 0 && result !== 1) throw new Error('VAD processing failed');
      return result === 1;
    },
    dispose() {
      if (disposed) return;
      new Int16Array(api.memory.buffer, ptr, 480).fill(0);
      api.free(ptr); api.fvad_free(handle); disposed = true;
    },
  };
}
