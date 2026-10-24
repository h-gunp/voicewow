function browserPlatform() {
  const devices = globalThis.navigator?.mediaDevices;
  return {
    getUserMedia: typeof devices?.getUserMedia === 'function' ? constraints => devices.getUserMedia(constraints) : undefined,
    createContext: typeof globalThis.AudioContext === 'function' ? () => new AudioContext() : undefined,
    createWorkletNode: typeof globalThis.AudioWorkletNode === 'function' ? context => new AudioWorkletNode(context, 'voicemate-meter') : undefined,
    isSecureContext: () => globalThis.isSecureContext !== false,
    now: () => performance.now(),
    setInterval: (fn, ms) => globalThis.setInterval(fn, ms),
    clearInterval: id => globalThis.clearInterval(id),
    isHidden: () => document.hidden,
    subscribeVisibility: fn => { document.addEventListener('visibilitychange', fn); return () => document.removeEventListener('visibilitychange', fn); },
    subscribeDeviceChange: fn => {
      devices?.addEventListener('devicechange', fn);
      return () => devices?.removeEventListener('devicechange', fn);
    },
  };
}
function errorReason(error) {
  return ({NotAllowedError:'permission_denied',SecurityError:'permission_denied',NotFoundError:'device_missing',NotReadableError:'device_busy',OverconstrainedError:'constraints_unavailable'})[error?.name] || error?.captureReason || 'processing_error';
}
function failure(reason) { return Object.assign(new Error(reason), {captureReason:reason}); }

/** Each start owns its resources. Cancelled permission/module promises cannot revive it. */
export function createCapture({onEvent, platform = browserPlatform()}) {
  let active = null;
  const current = session => active === session && !session.cancelled;
  async function release(s) {
    if (s.timer !== undefined) { platform.clearInterval(s.timer); s.timer = undefined; }
    s.unsubscribe?.(); s.unsubscribe = null;
    s.unsubscribeDevice?.(); s.unsubscribeDevice = null;
    for (const [target, type, fn] of s.listeners) target.removeEventListener(type, fn);
    s.listeners = [];
    if (s.node) { s.node.port.onmessage = null; s.node.onprocessorerror = null; s.node.port.close(); }
    for (const n of [s.source, s.node, s.gain]) { try { n?.disconnect(); } catch { /* Already disconnected. */ } }
    s.source = s.node = s.gain = null;
    for (const track of s.stream?.getTracks() || []) track.stop();
    s.stream = null;
    const context = s.context; s.context = null;
    try { if (context && context.state !== 'closed') await context.close(); } catch { /* Tracks are already stopped. */ }
  }
  async function end(s, state, reason) {
    if (!current(s)) return;
    active = null; s.cancelled = true;
    // Emit before asynchronous cleanup so an older session cannot overwrite a new one.
    onEvent({type:'state',state,...(reason ? {reason} : {})});
    await release(s);
  }
  function listen(s, target, type, fn) { target.addEventListener(type, fn); s.listeners.push([target,type,fn]); }
  function start() {
    if (active) return active.promise;
    const s = {cancelled:false,listeners:[]}; active = s;
    onEvent({type:'state',state:'requesting'});
    s.promise = (async () => {
      try {
        if (platform.isSecureContext?.() === false) throw failure('insecure_context');
        if (typeof platform.getUserMedia !== 'function' || typeof platform.createContext !== 'function' || typeof platform.createWorkletNode !== 'function') throw failure('unsupported');
        if (platform.isHidden()) throw failure('tab_hidden');
        s.unsubscribe = platform.subscribeVisibility(() => { if(platform.isHidden()) void end(s,'idle','tab_hidden'); });
        s.unsubscribeDevice = platform.subscribeDeviceChange?.(() => void end(s,'idle','device_changed'));
        // Create/resume within the start click's activation. Await after permission.
        s.context = platform.createContext();
        const resumed = s.context.resume().then(() => null, error => error);
        s.stream = await platform.getUserMedia({audio:{channelCount:1,autoGainControl:false,noiseSuppression:false,echoCancellation:false},video:false});
        if (!current(s)) { await release(s); return; }
        const track = s.stream.getAudioTracks()[0];
        if (!track || track.readyState === 'ended') throw failure('input_ended');
        if (track.muted) throw failure('input_muted');
        listen(s,track,'mute',()=>void end(s,'error','input_muted'));
        listen(s,track,'ended',()=>void end(s,'error','input_ended'));
        const resumeError = await resumed;
        if (!current(s)) { await release(s); return; }
        if (resumeError) throw resumeError;
        if (!s.context.audioWorklet) throw failure('unsupported');
        await s.context.audioWorklet.addModule(new URL('./capture-worklet.js', import.meta.url).href);
        if (!current(s)) { await release(s); return; }
        s.source = s.context.createMediaStreamSource(s.stream);
        s.node = platform.createWorkletNode(s.context);
        s.gain = s.context.createGain(); s.gain.gain.value = 0;
        s.lastFrame = platform.now();
        let lastSettingsKey;
        function publishSettings() {
          // Only non-identifying processing settings leave the audio bridge.
          const raw = track.getSettings(), settings = {contextSampleRate:s.context.sampleRate};
          for (const key of ['sampleRate','channelCount','autoGainControl','noiseSuppression','echoCancellation']) if (raw[key] !== undefined) settings[key] = raw[key];
          const settingsKey = JSON.stringify(settings);
          if (settingsKey !== lastSettingsKey) {
            lastSettingsKey = settingsKey;
            onEvent({type:'settings',settings});
          }
        }
        s.node.port.onmessage = ({data}) => {
          if (!current(s)) return;
          if (data?.type === 'error') { void end(s,'error','invalid_samples'); return; }
          if (data?.type !== 'level') return;
          if (!Number.isFinite(data.rms) || data.rms < 0 || !Number.isFinite(data.peak) || data.peak < 0 || !(data.dbfs === null || Number.isFinite(data.dbfs)) || !Number.isFinite(data.normalized) || data.normalized < 0 || data.normalized > 1 || !Number.isInteger(data.sampleCount) || data.sampleCount < 1) { void end(s,'error','invalid_samples'); return; }
          try { publishSettings(); } catch { void end(s,'error','processing_error'); return; }
          if (!current(s)) return;
          s.lastFrame = platform.now();
          onEvent({type:'level',rms:data.rms,peak:data.peak,dbfs:data.dbfs,normalized:data.normalized,sampleCount:data.sampleCount});
        };
        s.node.onprocessorerror = () => void end(s,'error','processing_error');
        s.source.connect(s.node); s.node.connect(s.gain); s.gain.connect(s.context.destination);
        s.timer = platform.setInterval(() => { if (platform.now() - s.lastFrame >= 1500) void end(s,'error','frame_timeout'); }, 250);
        publishSettings();
        onEvent({type:'state',state:'running'});
      } catch(error) {
        if (current(s)) await end(s,'error',errorReason(error));
        else await release(s);
      }
    })();
    return s.promise;
  }
  async function stop() {
    if (active) await end(active,'idle');
  }
  return {start,stop};
}

if (typeof window !== 'undefined') window.voiceMateAudio = {createCapture};
