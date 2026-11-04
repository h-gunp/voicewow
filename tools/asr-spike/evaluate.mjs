// Local public-fixture robustness experiment. No network or microphone access.
import sherpa from 'sherpa-onnx-node';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {locateScript} from '../../apps/client/web/prosody/script-alignment.js';
import {GUIDES} from '../../apps/client/web/prosody/guide-data.js';
const root=fileURLToPath(new URL('../../.local/asr-spike/',import.meta.url));
const rec=new sherpa.OnlineRecognizer({featConfig:{sampleRate:16000,featureDim:80},modelConfig:{
  transducer:{encoder:path.join(root,'encoder-epoch-99-avg-1.int8.onnx'),decoder:path.join(root,'decoder-epoch-99-avg-1.onnx'),joiner:path.join(root,'joiner-epoch-99-avg-1.int8.onnx')},
  tokens:path.join(root,'tokens.txt'),numThreads:1,provider:'cpu'},decodingMethod:'greedy_search'});
const refs=JSON.parse(fs.readFileSync(new URL('./evidence/native-report.json',import.meta.url))).results;
let seed=12345;
function noise(n){return Float32Array.from({length:n},()=>{seed=(1664525*seed+1013904223)>>>0;return (seed/4294967296-.5)*2;});}
function noisy(samples,snr){const out=noise(samples.length);const rms=a=>Math.sqrt(a.reduce((s,x)=>s+x*x,0)/a.length);const k=rms(samples)/rms(out)/10**(snr/20);return out.map((x,i)=>Math.max(-1,Math.min(1,samples[i]+x*k)));}
function decode(wave){const s=rec.createStream();for(let i=0;i<wave.samples.length;i+=2560){s.acceptWaveform({sampleRate:wave.sampleRate,samples:wave.samples.slice(i,i+2560)});while(rec.isReady(s))rec.decode(s);}s.acceptWaveform({sampleRate:wave.sampleRate,samples:new Float32Array(wave.sampleRate*2.4)});s.inputFinished();while(rec.isReady(s))rec.decode(s);return rec.getResult(s).text;}
const cases=[];
for(let i=0;i<4;i++) {
  const w=sherpa.readWave(path.join(root,`test_wavs/${i}.wav`));
  for(const snr of [null,10,0]) cases.push({name:`public-${i}-${snr===null?'clean':snr+'dB-synthetic-white-noise'}`,wave:{...w,samples:snr===null?w.samples:noisy(w.samples,snr)},script:refs[i].reference,kind:'speech'});
  const repeated=new Float32Array(w.samples.length*2+8000);repeated.set(w.samples);repeated.set(w.samples,w.samples.length+8000);
  cases.push({name:`public-${i}-repeated-audio-and-script`,wave:{...w,samples:repeated},script:refs[i].reference+' '+refs[i].reference,kind:'ambiguous-repeat'});
  cases.push({name:`public-${i}-wrong-script`,wave:w,script:'이번 발표는 우주 탐사 기술과 미래의 행성 자원 개발에 대한 내용입니다.',kind:'mismatch'});
}
for(const g of GUIDES){cases.push({name:`bundled-TTS-${g.id}`,wave:sherpa.readWave(fileURLToPath(new URL('../../apps/client/web/prosody/'+g.audioUrl,import.meta.url))),script:g.text,kind:'synthetic-speech'});}
cases.push({name:'additional-sensevoice-ko-untranscribed',wave:sherpa.readWave(path.join(root,'sensevoice-ko.wav')),script:refs[0].reference,kind:'additional-public-no-reference'});
for(const [name,samples] of [['silence',new Float32Array(80000)],['synthetic-white-noise',noise(80000).map(x=>x*.1)],['synthetic-tone',Float32Array.from({length:80000},(_,i)=>.1*Math.sin(2*Math.PI*440*i/16000))]])
  cases.push({name,wave:{sampleRate:16000,samples},script:refs[0].reference,kind:'synthetic-nonspeech'});
const results=cases.map(c=>{const text=decode(c.wave);return {name:c.name,kind:c.kind,seconds:c.wave.samples.length/c.wave.sampleRate,text,script:c.script,alignment:locateScript(c.script,text)};});
const report={note:'Small heterogeneous public/synthetic suite, not accuracy or real-noise benchmark. Additional Korean sample lacks a verified reference.',results};
fs.writeFileSync(new URL('./evidence/robustness-report.json',import.meta.url),JSON.stringify(report,null,2));
for(const r of results)console.log(JSON.stringify({name:r.name,kind:r.kind,status:r.alignment.status}));
