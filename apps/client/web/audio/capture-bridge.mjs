import { EnvironmentEstimator } from './environment-estimator.mjs';

function browserPlatform() {
  const devices = globalThis.navigator?.mediaDevices;
  return {
    getUserMedia: typeof devices?.getUserMedia === 'function' ? constraints => devices.getUserMedia(constraints) : undefined,
    createContext: typeof globalThis.AudioContext === 'function' ? () => {
      try { return new AudioContext({sampleRate:48000}); }
      catch { return new AudioContext(); }
    } : undefined,
    createWorkletNode: typeof globalThis.AudioWorkletNode === 'function' ? context => new AudioWorkletNode(context, 'voicemate-meter') : undefined,
    createNoiseReductionNode: async (context, signal) => {
      const {createNoiseReductionNode} = await import('./noise-reduction.mjs');
      return createNoiseReductionNode(context, signal);
    },
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
function readTrackSettings(track) {
  try { return track.getSettings(); } catch { throw failure('settings_unavailable'); }
}
function disposeNode(node) {
  if (!node) return;
  node.port.onmessage = null; node.onprocessorerror = null;
  try { node.port.postMessage?.({type:'dispose'}); } catch { /* A failed processor may already have closed its port. */ }
  node.port.close();
  try { node.disconnect(); } catch { /* Already disconnected. */ }
}

/** Each start owns its resources. Cancelled permission/module promises cannot revive it. */
export function createCapture({onEvent, platform = browserPlatform()}) {
  let active = null, nextSession = 0;
  const current = session => active === session && !session.cancelled;
  async function prepareNoiseNode(s) {
    const loading = new AbortController();
    const cancel = () => loading.abort();
    listen(s, s.abort.signal, 'abort', cancel);
    // Include the lazy JS import in the deadline, before the WASM loader exists.
    const timer = setTimeout(() => loading.abort(failure('load_timeout')), 10000);
    let rejectCancelled;
    const cancelled = new Promise((_, reject) => {
      rejectCancelled = () => reject(loading.signal.reason);
      loading.signal.addEventListener('abort', rejectCancelled, {once:true});
    });
    try {
      if (s.abort.signal.aborted) cancel();
      const prepared = platform.createNoiseReductionNode(s.context, loading.signal).then(node => {
        if (loading.signal.aborted) { disposeNode(node); throw loading.signal.reason; }
        return node;
      });
      return await Promise.race([prepared, cancelled]);
    } finally {
      clearTimeout(timer);
      loading.signal.removeEventListener('abort', rejectCancelled);
    }
  }
  async function release(s) {
    s.abort.abort();
    if (s.timer !== undefined) { platform.clearInterval(s.timer); s.timer = undefined; }
    s.unsubscribe?.(); s.unsubscribe = null;
    s.unsubscribeDevice?.(); s.unsubscribeDevice = null;
    for (const [target, type, fn] of s.listeners) target.removeEventListener(type, fn);
    s.listeners = [];
    disposeNode(s.node);
    for (const n of [s.source, s.gain]) { try { n?.disconnect(); } catch { /* Already disconnected. */ } }
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
  function start(noiseReductionEnabled = true) {
    if (active) return active.promise;
    const s = {cancelled:false,listeners:[],hasFrame:false,abort:new AbortController(),sessionId:++nextSession, settingsRevision:0, estimator:new EnvironmentEstimator()}; active = s;
    onEvent({type:'state',state:'requesting'});
    s.promise = (async () => {
      try {
        if (platform.isSecureContext?.() === false) throw failure('insecure_context');
        if (typeof platform.getUserMedia !== 'function' || typeof platform.createContext !== 'function' || typeof platform.createWorkletNode !== 'function') throw failure('unsupported');
        if (platform.isHidden()) throw failure('tab_hidden');
        s.unsubscribe = platform.subscribeVisibility(() => { if(platform.isHidden()) void end(s,'idle','tab_hidden'); });
        s.unsubscribeDevice = platform.subscribeDeviceChange?.(() => {
          // Permission can expose a new device list without changing the captured microphone.
          if (!current(s) || !s.track) return;
          try {
            const track = s.stream.getAudioTracks()[0];
            if (track !== s.track || track.readyState !== 'live' || track.muted) {
              void end(s,'idle','device_changed'); return;
            }
            const deviceId = readTrackSettings(track).deviceId || null;
            if (s.deviceId && deviceId === s.deviceId) return;
            if (!s.hasFrame && !s.deviceId) { s.deviceId = deviceId; return; }
            // Without a stable identity after audio starts, do not mix uncertain inputs.
            void end(s,'idle','device_changed');
          } catch(error) { void end(s,'error',errorReason(error)); }
        });
        // Create/resume within the start click's activation. Await after permission.
        s.context = platform.createContext();
        let resumed;
        try { resumed = Promise.resolve(s.context.resume()).then(() => null, error => error); }
        catch { throw failure('context_resume_failed'); }
        s.stream = await platform.getUserMedia({audio:{channelCount:1,autoGainControl:false,noiseSuppression:false,echoCancellation:false},video:false});
        if (!current(s)) { await release(s); return; }
        const track = s.stream.getAudioTracks()[0];
        if (!track || track.readyState === 'ended') throw failure('input_ended');
        if (track.muted) throw failure('input_muted');
        s.track = track;
        s.deviceId = readTrackSettings(track).deviceId || null;
        listen(s,track,'mute',()=>void end(s,'error','input_muted'));
        listen(s,track,'ended',()=>void end(s,'error','input_ended'));
        if (s.context.state !== 'running') onEvent({type:'state',state:'requesting',reason:'context_resuming'});
        const schedule = platform.setTimeout || globalThis.setTimeout;
        const clear = platform.clearTimeout || globalThis.clearTimeout;
        let resumeTimer, cancelResume;
        const timeout = new Promise(resolve => { resumeTimer = schedule(() => resolve(failure('context_resume_timeout')), 5000); });
        const cancelled = new Promise(resolve => { cancelResume = () => resolve(failure('cancelled')); s.abort.signal.addEventListener('abort',cancelResume,{once:true}); });
        if (s.abort.signal.aborted) cancelResume();
        let resumeError;
        try { resumeError = await Promise.race([resumed, timeout, cancelled]); }
        finally { clear(resumeTimer); s.abort.signal.removeEventListener('abort',cancelResume); }
        if (!current(s)) { await release(s); return; }
        if (resumeError) throw failure(resumeError.captureReason === 'context_resume_timeout' ? 'context_resume_timeout' : 'context_resume_failed');
        if (s.context.state !== 'running') throw failure('context_not_running');
        if (!s.context.audioWorklet) throw failure('unsupported');
        let lastSettingsKey;
        function publishSettings() {
          // Only non-identifying processing settings leave the audio bridge.
          const raw = readTrackSettings(track), settings = {contextSampleRate:s.context.sampleRate, contextState:s.context.state};
          for (const key of ['sampleRate','channelCount','autoGainControl','noiseSuppression','echoCancellation']) if (raw[key] !== undefined) settings[key] = raw[key];
          settings.noiseReductionState = s.noiseReductionState;
          if (s.node?.vadStatus) settings.vadStatus = s.node.vadStatus;
          if (s.noiseReductionReason) settings.noiseReductionReason = s.noiseReductionReason;
          const settingsKey = JSON.stringify(settings);
          if (settingsKey !== lastSettingsKey) {
            if (lastSettingsKey !== undefined) {
              s.estimator = new EnvironmentEstimator(); s.analysisOrigin = null;
              s.speechFrames = 0;
              s.settingsRevision++;
            }
            lastSettingsKey = settingsKey;
            onEvent({type:'settings',settings});
          }
        }
        if (!noiseReductionEnabled) {
          s.noiseReductionState = 'disabled';
        } else if (typeof platform.createNoiseReductionNode === 'function') {
          s.noiseReductionState = 'loading';
          publishSettings();
          try {
            s.node = await prepareNoiseNode(s);
          } catch (error) {
            if (!current(s)) { await release(s); return; }
            s.noiseReductionReason = ['unsupported','unsupported_sample_rate','load_failed','load_timeout'].includes(error?.captureReason) ? error.captureReason : 'load_failed';
          }
          if (!current(s)) { await release(s); return; }
          s.noiseReductionState = s.node ? 'active' : 'unavailable';
        } else {
          s.noiseReductionState = 'unavailable';
          s.noiseReductionReason = 'unsupported';
        }
        if (!s.node) {
          await s.context.audioWorklet.addModule(new URL('./capture-worklet.js', import.meta.url).href);
          if (!current(s)) { await release(s); return; }
          s.node = platform.createWorkletNode(s.context);
        }
        s.source = s.context.createMediaStreamSource(s.stream);
        s.gain = s.context.createGain(); s.gain.gain.value = 0;
        s.lastFrame = platform.now();
        s.node.port.onmessage = ({data}) => {
          if (!current(s)) return;
          if (data?.type === 'error') { void end(s,'error',s.noiseReductionState === 'active' ? 'noise_reduction_failed' : 'invalid_samples'); return; }
          if (data?.type === 'analysis_reset') {
            s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.lastAnalysisSeq = undefined;
            s.analysisOrigin = null; s.speechFrames = 0; s.estimator.resetEpoch();
            onEvent({type:'analysis',analysis:{state:'held',meterState:'unavailable',reason:'input_gap'}}); return;
          }
          if (data?.type === 'analysis_unavailable') {
            s.estimator = new EnvironmentEstimator();
            s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.speechFrames = 0;
            s.node.vadStatus = 'runtime_failed';
            try { publishSettings(); } catch(error) { void end(s,'error',errorReason(error)); return; }
            onEvent({type:'analysis',analysis:{state:'unavailable',meterState:'unavailable',reason:'vad_runtime_failed'}}); return;
          }
          if (data?.type === 'analysis') {
            try {
              publishSettings();
              const settings = readTrackSettings(track);
              if (s.node.vadStatus && s.node.vadStatus !== 'ready') {
                s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.speechFrames = 0;
                onEvent({type:'analysis',analysis:{state:'unavailable',meterState:'unavailable',reason:'vad_unavailable'}}); return;
              }
              if (s.noiseReductionState !== 'active') {
                s.estimator = new EnvironmentEstimator(); s.analysisOrigin = null;
                s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.speechFrames = 0;
                onEvent({type:'analysis',analysis:{state:'unavailable',meterState:'unavailable',reason:'noise_reduction_unavailable'}}); return;
              }
              const environmentSupported = ['autoGainControl','noiseSuppression','echoCancellation'].every(key=>settings[key] === false);
              const now = platform.now();
              if (!Number.isSafeInteger(data.seq) || data.seq < 0 || data.sampleStart !== data.seq*480 || data.sampleEnd !== (data.seq+1)*480 || typeof data.clipped !== 'boolean' || !Number.isFinite(data.sampleTime) || !Number.isFinite(s.context.currentTime)) throw new Error('invalid analysis');
              const origin = data.sampleTime - data.sampleEnd/48000;
              if (s.analysisOrigin == null) s.analysisOrigin = origin;
              if (Math.abs(s.analysisOrigin-origin) > .001) throw new Error('analysis clock changed');
              const age = (s.context.currentTime-data.sampleTime)*1000;
              if (age > 1000 || age < -250) { s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.speechFrames = 0; s.estimator.hold(); onEvent({type:'analysis',analysis:{state:'held',meterState:'unavailable',reason:'analysis_stale'}}); return; }
              if (data.meterRms !== undefined && (!Number.isFinite(data.meterRms) || data.meterRms < 0)) throw new Error('invalid meter');
              if (!Number.isFinite(data.power) || data.power < 0 || !['speech','nonSpeech','uncertain'].includes(data.speech)) throw new Error('invalid analysis');
              if (s.lastAnalysisSeq !== undefined && data.seq <= s.lastAnalysisSeq) return;
              if (s.lastAnalysisSeq !== undefined && data.seq !== s.lastAnalysisSeq + 1) s.speechFrames = 0;
              s.lastAnalysisSeq = data.seq; s.lastAnalysisAt = now;
              if (environmentSupported) s.estimator.add(data);
              const snapshot = environmentSupported ? s.estimator.snapshot() : {state:'unavailable',reason:'processing_settings',speech:data.clipped?'uncertain':data.speech,noiseDbfs:null,voiceDbfs:null,offset:null};
              const validSpeech = age <= 200 && !data.clipped && snapshot.speech === 'speech' && data.meterRms > 0;
              // Experimental 30 ms onset confirmation; the VAD threshold is unchanged.
              s.speechFrames = validSpeech ? Math.min((s.speechFrames || 0) + 1, 3) : 0;
              const meterState = age > 200 || data.clipped ? 'unavailable' : snapshot.speech !== 'speech' ? snapshot.speech : !validSpeech ? 'unavailable' : s.speechFrames < 3 ? 'confirming' : 'speech';
              const meterDbfs = meterState === 'speech' ? 20*Math.log10(data.meterRms) : null;
              const signature = `${snapshot.state}/${snapshot.speech}/${meterState}`;
              if (signature !== s.lastAnalysisSignature || data.seq%10===0) {
                s.lastAnalysisSignature = signature;
                onEvent({type:'analysis',analysis:{...snapshot,meterState,meterDbfs,sessionId:s.sessionId,deviceEpoch:s.sessionId,settingsRevision:s.settingsRevision,seq:data.seq,sampleStart:data.sampleStart,sampleEnd:data.sampleEnd,sampleTime:data.sampleTime,receivedAt:now}});
              }
            } catch(error) { if (error?.captureReason === 'settings_unavailable') { void end(s,'error','settings_unavailable'); return; } s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.speechFrames = 0; s.estimator.hold(); onEvent({type:'analysis',analysis:{state:'unavailable',meterState:'unavailable',reason:'invalid_analysis'}}); }
            return;
          }
          if (data?.type !== 'level') return;
          if (!Number.isFinite(data.rms) || data.rms < 0 || !Number.isFinite(data.peak) || data.peak < 0 || !(data.dbfs === null || Number.isFinite(data.dbfs)) || !Number.isFinite(data.normalized) || data.normalized < 0 || data.normalized > 1 || !Number.isInteger(data.sampleCount) || data.sampleCount < 1) { void end(s,'error','invalid_samples'); return; }
          try { publishSettings(); } catch(error) { void end(s,'error',errorReason(error)); return; }
          if (!current(s)) return;
          s.lastFrame = platform.now();
          s.hasFrame = true;
          onEvent({type:'level',rms:data.rms,peak:data.peak,dbfs:data.dbfs,normalized:data.normalized,sampleCount:data.sampleCount});
        };
        s.node.onprocessorerror = () => void end(s,'error',s.noiseReductionState === 'active' ? 'noise_reduction_failed' : 'processing_error');
        s.source.connect(s.node); s.node.connect(s.gain); s.gain.connect(s.context.destination);
        s.timer = platform.setInterval(() => {
          const now = platform.now();
          try { publishSettings(); } catch(error) { void end(s,'error',errorReason(error)); return; }
          if (now - s.lastFrame >= 1500) void end(s,'error','frame_timeout');
          else if (s.lastAnalysisAt !== undefined && now-s.lastAnalysisAt >= 250) {
            s.lastAnalysisAt = undefined; s.lastAnalysisSignature = null; s.speechFrames = 0; s.estimator.hold();
            onEvent({type:'analysis',analysis:{state:'held',meterState:'unavailable',reason:'analysis_stale'}});
          }
        }, 250);
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
