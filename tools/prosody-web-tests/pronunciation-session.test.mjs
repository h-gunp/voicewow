import test from 'node:test';
import assert from 'node:assert/strict';
import { createPronunciationSession, createPronunciationBridge } from '../../apps/client/web/pronunciation/bridge.mjs';

const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };

function fixture(t, overrides = {}) {
  let capture;
  const events = [], played = [];
  const client = { ready: false,
    async prepare(progress) { progress?.('준비 중이다.'); this.ready = true; },
    async recognize(samples, sampleRate) { events.push(['recognize', samples.length, sampleRate]); return { phones: [{ phone: 'k' }, { phone: 'a' }] }; },
    cancel() { events.push(['worker-stop']); this.ready = false; }, ...overrides.client };
  const recorder = { async start() { events.push(['start']); }, async stop() { events.push(['tail']); return { samples: new Float32Array(3201).fill(.2), sampleRate: 16000 }; }, async cancel() { events.push(['mic-stop']); }, ...overrides.recorder };
  const old = globalThis.Audio;
  globalThis.Audio = class { constructor(url) { this.url = url; played.push(this); } async play() { this.playing = true; } pause() { this.playing = false; } removeAttribute() {} load() {} };
  t.after(() => old === undefined ? delete globalThis.Audio : globalThis.Audio = old);
  const session = createPronunciationSession({ client, recorderFactory: callbacks => { capture = callbacks; return recorder; } });
  t.after(() => session.dispose());
  return { session, client, events, played, capture: () => capture };
}

test('preparation never opens mic; finish sends all final PCM and exposes phones only', async t => {
  const f = fixture(t);
  const progress = [];
  await f.session.prepare(message => progress.push(message));
  assert.equal(f.events.length, 0);
  assert.equal(progress.length, 1);
  await f.session.start(() => {}, () => {});
  assert.deepEqual(await f.session.finish(), ['k', 'a']);
  assert.deepEqual(f.events, [['start'], ['tail'], ['recognize', 3201, 16000]]);
  const replay = f.session.play();
  const cancelledReplay = assert.rejects(replay, { name: 'AbortError' });
  assert.equal(f.played[0].playing, true);
  await f.session.cancel();
  await cancelledReplay;
  assert.equal(f.played[0].playing, false);
  await assert.rejects(f.session.play(), /녹음/);
  assert.ok(f.events.some(event => event[0] === 'worker-stop'));
});

test('replay remains pending until the recording ends', async t => {
  const f = fixture(t);
  await f.session.prepare(); await f.session.start(() => {}, () => {}); await f.session.finish();
  let completed = false;
  const replay = f.session.play().then(() => { completed = true; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(completed, false);
  f.played[0].onended();
  await replay;
  assert.equal(completed, true);
});

test('late replay errors reject and a new recording stops pending replay', async t => {
  const f = fixture(t);
  await f.session.prepare(); await f.session.start(() => {}, () => {}); await f.session.finish();
  const failed = assert.rejects(f.session.play(), /재생/);
  f.played[0].onerror?.();
  await failed;
  const interrupted = assert.rejects(f.session.play(), { name: 'AbortError' });
  await f.session.start(() => {}, () => {});
  await interrupted;
  assert.equal(f.played[1].playing, false);
});

test('limit callback is single-use and stale callbacks cannot affect a retry', async t => {
  const f = fixture(t); let limited = 0, failed = 0;
  await f.session.prepare();
  await f.session.start(() => limited++, () => failed++);
  const stale = f.capture();
  stale.onLimit(); stale.onLimit();
  assert.equal(limited, 1);
  await f.session.finish();
  await f.session.start(() => limited++, () => failed++);
  stale.onLimit(); stale.onError(new Error('old'));
  assert.equal(limited, 1); assert.equal(failed, 0);
});

test('voice activity reports changed chunk decisions without changing phones or accepting stale activity', async t => {
  const f = fixture(t), states = [];
  await f.session.prepare();
  await f.session.start(() => {}, () => {}, state => states.push(state));
  const first = f.capture();
  assert.equal(typeof first.onChunk, 'function');
  const emit = (speechFrames, nonSpeechFrames, uncertainFrames) => first.onChunk({speech: {
    speechFrames, nonSpeechFrames, uncertainFrames, totalFrames: speechFrames + nonSpeechFrames + uncertainFrames,
  }});
  emit(0, 10, 0); emit(0, 20, 0); emit(3, 27, 0); emit(3, 27, 10);
  assert.deepEqual(states, ['nonSpeech', 'speech', 'uncertain']);
  assert.deepEqual(await f.session.finish(), ['k', 'a']);
  emit(13, 27, 10);
  await f.session.start(() => {}, () => {}, state => states.push(state));
  emit(23, 27, 10);
  await f.session.cancel();
  f.capture().onChunk({speech: {speechFrames: 10, nonSpeechFrames: 0, uncertainFrames: 0, totalFrames: 10}});
  assert.deepEqual(states, ['nonSpeech', 'speech', 'uncertain']);
});

test('cancelling inference rejects its late result and clears replay', async t => {
  const inference = deferred(), reached = deferred();
  const f = fixture(t, { client: { recognize() { reached.resolve(); return inference.promise; } } });
  await f.session.prepare(); await f.session.start(() => {}, () => {});
  const pending = f.session.finish();
  const rejected = assert.rejects(pending, { name: 'AbortError' });
  await reached.promise; await f.session.cancel();
  inference.resolve({ phones: [{ phone: 'stale' }] });
  await rejected;
  await assert.rejects(f.session.play(), /녹음/);
});

test('microphone permission errors become Korean and dispose allows a fresh global session', async t => {
  const f = fixture(t, { recorder: { async start() { throw new DOMException('Denied', 'NotAllowedError'); } } });
  await f.session.prepare();
  await assert.rejects(f.session.start(() => {}, () => {}), /마이크 권한/);
  const sessions = [];
  const bridge = createPronunciationBridge(() => {
    const session = { disposed: false, async prepare() {}, async cancel() {}, async dispose() { this.disposed = true; } };
    sessions.push(session); return session;
  });
  await bridge.prepare(); await bridge.dispose(); await bridge.prepare();
  assert.equal(sessions.length, 2); assert.equal(sessions[0].disposed, true);
});

test('old owner dispose cannot cancel the session that replaced it', async () => {
  const sessions = [];
  const bridge = createPronunciationBridge(() => {
    const session = { cancelled: 0, async prepare() {}, async cancel() { this.cancelled++; }, async dispose() { this.cancelled++; } };
    sessions.push(session); return session;
  });
  const first = bridge.createSession(), second = bridge.createSession();
  await first.prepare(); await second.prepare();
  assert.equal(sessions[0].cancelled, 1);
  await first.dispose();
  assert.equal(sessions[1].cancelled, 0);
});

test('cancel while model preparation is pending cannot revive ready state', async t => {
  const prepared = deferred();
  const f = fixture(t, { client: { async prepare() { await prepared.promise; this.ready = true; } } });
  const pending = f.session.prepare();
  const rejected = assert.rejects(pending, { name: 'AbortError' });
  await f.session.cancel(); prepared.resolve(); await rejected;
  await assert.rejects(f.session.start(() => {}, () => {}), /준비/);
  assert.ok(!f.events.some(event => event[0] === 'start'));
});

test('a stale owner waiting for microphone cleanup cannot start its model later', async () => {
  const cleanup = deferred(), sessions = [];
  const bridge = createPronunciationBridge(() => {
    const index = sessions.length;
    const session = { prepared: 0, async prepare() { this.prepared++; },
      async cancel() { if (index === 0) await cleanup.promise; }, async dispose() {} };
    sessions.push(session); return session;
  });
  const first = bridge.createSession(), second = bridge.createSession(), third = bridge.createSession();
  await first.prepare();
  const stale = second.prepare();
  const rejected = assert.rejects(stale, { name: 'AbortError' });
  await third.prepare(); cleanup.resolve(); await rejected;
  assert.equal(sessions[1].prepared, 0);
  assert.equal(sessions[2].prepared, 1);
});
