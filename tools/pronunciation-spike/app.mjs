import { createPhoneClient } from './client.mjs';
import { createRecorder } from './recording.mjs';
import { to16kHz, encodeWav, decodeWav } from './audio.mjs';

const el = id => document.getElementById(id);
const client = createPhoneClient();
const recorder = createRecorder({ onLimit: () => { void stopAndAnalyze(); }, onError: error => showError(error, generation) });
let state = 'idle', generation = 0, timer, startedAt = 0, audioUrl = null;

function update(next, message) {
  state = next;
  el('status').textContent = message;
  el('prepare').disabled = next !== 'idle';
  el('record').disabled = !['ready', 'recording'].includes(next);
  el('record').textContent = next === 'recording' ? '■ 녹음 종료·분석' : '● 녹음 시작';
  el('cancel').disabled = ['idle', 'cancelling'].includes(next);
  el('file').disabled = next !== 'ready';
  el('prompt').disabled = !['idle', 'ready'].includes(next);
  el('playback-section').hidden = !audioUrl || ['recording', 'starting'].includes(next);
  if (next !== 'recording') { clearInterval(timer); timer = null; }
}

function clearResult() {
  el('result').hidden = true;
  el('transcript').replaceChildren(); el('notes').replaceChildren(); el('phones').textContent = '';
  el('playback').pause(); el('playback').removeAttribute('src'); el('playback').load();
  if (audioUrl) URL.revokeObjectURL(audioUrl);
  audioUrl = null; el('playback-section').hidden = true; el('timer').textContent = '최대 20초';
}

function showError(error, ticket) {
  if (ticket !== generation || error?.name === 'AbortError') return;
  void recorder.cancel();
  const message = error?.name === 'NotAllowedError' ? '마이크 권한이 필요하다. 브라우저 권한을 확인한 뒤 다시 시도하면 된다.'
    : error?.name === 'NotFoundError' ? '사용할 마이크를 찾지 못했다.'
      : /[가-힣]/u.test(error?.message ?? '') ? error.message : '녹음 또는 분석이 중단됐다. 마이크 연결을 확인하고 다시 시도하면 된다.';
  update(client.ready ? 'ready' : 'idle', message);
}

async function analyze(recording, ticket) {
  const samples = await to16kHz(recording.samples, recording.sampleRate);
  if (ticket !== generation) return;
  audioUrl = URL.createObjectURL(new Blob([encodeWav(recording.samples, recording.sampleRate)], { type: 'audio/wav' }));
  el('playback').src = audioUrl;
  el('playback-section').hidden = false;
  const result = await client.recognize(samples, 16000);
  if (ticket !== generation) return;
  const notes = new Set();
  for (const segment of result.display.segments) {
    const span = document.createElement('span'); span.textContent = segment.text;
    if (segment.uncertain) { span.className = 'ambiguous'; span.title = segment.notes.join(' · '); }
    el('transcript').append(span);
    for (const note of segment.notes) notes.add(note);
  }
  if (!result.display.text) el('transcript').textContent = '인식된 음소가 없다.';
  for (const note of notes) { const li = document.createElement('li'); li.textContent = note; el('notes').append(li); }
  el('phones').textContent = result.phones.map(item => item.phone).join(' ') || '없음';
  el('timing').textContent = `음성 ${result.duration.toFixed(1)}초 · 분석 ${(result.inferenceMs / 1000).toFixed(1)}초`;
  el('result').hidden = false;
  update('ready', '분석을 마쳤다. 실제 녹음과 비교해야 하며, 정답·오답 판정은 아직 하지 않는다.');
}

async function stopAndAnalyze() {
  if (state !== 'recording') return;
  const ticket = generation;
  update('analyzing', '녹음을 마무리하고 기기 안에서 분석 중이다.');
  try { const recording = await recorder.stop(); if (ticket === generation) await analyze(recording, ticket); }
  catch (error) { showError(error, ticket); }
}

el('prepare').addEventListener('click', async () => {
  if (state !== 'idle') return;
  const ticket = ++generation;
  update('preparing', '이 PC의 모델 파일을 확인하고 준비 중이다.');
  try { await client.prepare(); if (ticket === generation) update('ready', '준비됐다. 마이크를 누르고 문장을 읽으면 된다.'); }
  catch (error) { showError(error, ticket); }
});

el('record').addEventListener('click', async () => {
  if (state === 'recording') { await stopAndAnalyze(); return; }
  if (state !== 'ready') return;
  const ticket = ++generation; clearResult();
  update('starting', '마이크 권한과 입력을 확인 중이다.');
  try {
    await recorder.start();
    if (ticket !== generation) return;
    update('recording', '녹음 중이다. 다시 누르면 종료하고 분석한다.');
    startedAt = performance.now();
    const tick = () => { el('timer').textContent = `${Math.min(20, (performance.now() - startedAt) / 1000).toFixed(1)} / 20초`; };
    tick(); timer = setInterval(tick, 100);
  } catch (error) { showError(error, ticket); }
});

el('file').addEventListener('change', async () => {
  const file = el('file').files?.[0]; el('file').value = '';
  if (!file || state !== 'ready') return;
  const ticket = ++generation; clearResult();
  update('analyzing', '기기 안에서 WAV 파일을 읽고 분석 중이다.');
  try {
    await recorder.cancel();
    if (ticket !== generation) return;
    if (file.size > 16000000) throw new Error('16MB 이하의 16비트 PCM WAV 파일이 필요하다.');
    const recording = decodeWav(await file.arrayBuffer());
    if (ticket === generation) await analyze(recording, ticket);
  } catch (error) { showError(error, ticket); }
});

async function cancel() {
  const ticket = ++generation;
  update('cancelling', '녹음과 분석을 정리 중이다.');
  client.cancel(); clearResult(); await recorder.cancel();
  if (ticket === generation) update('idle', '취소했다. 모델을 다시 준비하면 된다.');
}
el('cancel').addEventListener('click', () => { void cancel(); });
window.addEventListener('pagehide', () => { void cancel(); });
document.addEventListener('visibilitychange', () => { if (document.hidden) void cancel(); });
