import { createPhoneClient } from './client.mjs';
import { createRecorder } from './recording.mjs';
import { encodeWav, to16kHz } from './audio.mjs';

const aborted = () => new DOMException('발음 연습을 취소했다.', 'AbortError');
const koreanError = error => {
  if (error?.name === 'AbortError') return error;
  const message = error?.name === 'NotAllowedError' ? '마이크 권한이 필요하다. 브라우저 권한을 확인하고 다시 시도해야 한다.'
    : error?.name === 'NotFoundError' ? '사용할 마이크를 찾지 못했다.'
      : /[가-힣]/u.test(error?.message ?? '') ? error.message
        : '녹음 또는 분석이 중단됐다. 마이크 연결과 기기 메모리를 확인하고 다시 시도해야 한다.';
  return new Error(message);
};

export function createPronunciationSession({ client = createPhoneClient(), recorderFactory = createRecorder } = {}) {
  let generation = 0, phase = 'idle', recorder, playback, playbackUrl, pendingFinish, rejectPlayback;
  const check = ticket => { if (ticket !== generation || phase === 'disposed') throw aborted(); };
  const clearPlayback = () => {
    rejectPlayback?.(aborted());
    playback?.pause();
    playback?.removeAttribute('src');
    playback?.load();
    playback = undefined;
    if (playbackUrl) URL.revokeObjectURL(playbackUrl);
    playbackUrl = undefined;
  };

  async function cancel() {
    ++generation;
    if (phase !== 'disposed') phase = 'idle';
    pendingFinish = undefined;
    client.cancel();
    clearPlayback();
    const previous = recorder;
    recorder = undefined;
    await previous?.cancel();
  }

  return {
    async prepare(onProgress) {
      if (phase === 'disposed') throw aborted();
      if (!['idle', 'ready', 'result'].includes(phase)) throw new Error('이전 발음 작업이 진행 중이다.');
      const ticket = ++generation;
      phase = 'preparing';
      try {
        await client.prepare(message => { if (ticket === generation) onProgress?.(message); });
        check(ticket); phase = 'ready';
      } catch (error) {
        if (ticket === generation) phase = 'idle';
        throw koreanError(error);
      }
    },
    async start(onLimit, onError) {
      if (!client.ready || !['ready', 'result'].includes(phase)) throw new Error('발음 모델을 먼저 준비해야 한다.');
      const ticket = ++generation;
      clearPlayback(); pendingFinish = undefined;
      phase = 'starting';
      let limited = false;
      const current = recorderFactory({
        onLimit: () => {
          if (ticket !== generation || phase !== 'recording' || limited) return;
          limited = true;
          onLimit?.();
        },
        onError: error => {
          if (ticket !== generation || !['starting', 'recording', 'analyzing'].includes(phase)) return;
          void cancel();
          onError?.(koreanError(error).message);
        },
      });
      recorder = current;
      try { await current.start(); check(ticket); phase = 'recording'; }
      catch (error) {
        if (ticket === generation) { phase = client.ready ? 'ready' : 'idle'; recorder = undefined; }
        await current.cancel();
        throw koreanError(error);
      }
    },
    finish() {
      if (pendingFinish) return pendingFinish;
      if (phase !== 'recording') return Promise.reject(new Error('먼저 발음을 녹음해야 한다.'));
      const ticket = generation, current = recorder;
      phase = 'analyzing';
      pendingFinish = (async () => {
        try {
          const recording = await current.stop();
          check(ticket);
          const samples = await to16kHz(recording.samples, recording.sampleRate);
          check(ticket);
          playbackUrl = URL.createObjectURL(new Blob([encodeWav(recording.samples, recording.sampleRate)], { type: 'audio/wav' }));
          const result = await client.recognize(samples, 16000);
          check(ticket);
          if (!Array.isArray(result?.phones) || result.phones.some(item => typeof item?.phone !== 'string')) throw new Error('분석 결과 형식이 올바르지 않다.');
          phase = 'result';
          return result.phones.map(item => item.phone);
        } catch (error) {
          if (ticket === generation) { clearPlayback(); phase = client.ready ? 'ready' : 'idle'; pendingFinish = undefined; }
          throw koreanError(error);
        }
      })();
      return pendingFinish;
    },
    async play() {
      if (phase !== 'result' || !playbackUrl) throw new Error('다시 들을 녹음이 없다.');
      const ticket = generation;
      rejectPlayback?.(aborted());
      playback?.pause();
      const current = new Audio(playbackUrl);
      playback = current;
      try {
        await new Promise((resolve, reject) => {
          const finish = error => {
            current.onended = current.onerror = null;
            if (playback === current) rejectPlayback = undefined;
            current.pause();
            error ? reject(error) : resolve();
          };
          rejectPlayback = finish;
          current.onended = () => finish();
          current.onerror = () => finish(new Error('녹음을 재생하지 못했다. 다시 시도해야 한다.'));
          try { Promise.resolve(current.play()).catch(finish); }
          catch (error) { finish(error); }
        });
        check(ticket);
      }
      catch (error) { current.pause(); throw koreanError(error); }
    },
    cancel,
    async dispose() { phase = 'disposed'; await cancel(); },
  };
}

export function createPronunciationBridge(factory = createPronunciationSession) {
  let active, defaultSession;
  function createSession() {
    const session = factory();
    let generation = 0, disposed = false;
    const check = () => {
      if (disposed || active !== owner) throw aborted();
    };
    const owner = {
      async prepare(progress) {
        if (disposed) throw aborted();
        const ticket = ++generation;
        if (active !== owner) {
          const previous = active;
          active = owner;
          await previous?.cancel();
        }
        check();
        if (ticket !== generation) throw aborted();
        await session.prepare(progress);
      },
      async start(onLimit, onError) { check(); await session.start(onLimit, onError); },
      async finish() { check(); return session.finish(); },
      async play() { check(); await session.play(); },
      async cancel() {
        ++generation;
        if (active === owner) active = undefined;
        await session.cancel();
      },
      async dispose() {
        disposed = true; ++generation;
        if (active === owner) active = undefined;
        await session.dispose();
      },
    };
    return owner;
  }
  const current = () => defaultSession ??= createSession();
  return {
    createSession,
    prepare: progress => current().prepare(progress),
    start: (onLimit, onError) => current().start(onLimit, onError),
    finish: () => current().finish(),
    play: () => current().play(),
    async cancel() { await active?.cancel(); },
    async dispose() {
      const previous = active;
      await previous?.dispose();
      if (defaultSession && defaultSession !== previous) await defaultSession.dispose();
      defaultSession = undefined;
    },
  };
}

globalThis.voiceMatePronunciation = createPronunciationBridge();
globalThis.addEventListener?.('pagehide', () => { void globalThis.voiceMatePronunciation.cancel(); });
globalThis.document?.addEventListener('visibilitychange', () => {
  if (document.hidden) void globalThis.voiceMatePronunciation.cancel();
});
