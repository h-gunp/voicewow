import {readFile} from 'node:fs/promises';
import {createNoiseMeter} from '../apps/client/web/audio/noise-reducer.mjs';

const vb = await readFile(new URL('../apps/client/web/audio/vendor/libfvad/libfvad.wasm', import.meta.url));
const rb = await readFile(new URL('../apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', import.meta.url));
const length = 48000 * 4;
function noise(seed) { return () => { seed = (Math.imul(seed,1664525)+1013904223)>>>0; return seed / 4294967296 * 2 - 1; }; }
function burst(starts, duration, amp, background = 0) {
  const rand = noise(98765), data = Float32Array.from({length}, () => background * rand());
  for (const start of starts) for (let i=0; i<duration; i++) data[start*48+i] += amp * rand() * Math.exp(-i/(duration/4));
  return data;
}
const inputs = {
  silence: new Float32Array(length),
  single_impulse: (() => {const a=new Float32Array(length); a[48000]=.9; return a;})(),
  repeated_impulse: (() => {const a=new Float32Array(length); for(let i=24000;i<length;i+=24000)a[i]=.9; return a;})(),
  single_burst_10ms: burst([1000],480,.9),
  repeated_burst_10ms: burst([500,1000,1500,2000,2500,3000],480,.9),
  bursts_with_noise: burst([500,1000,1500,2000,2500,3000],480,.9,.02),
  stationary_low: burst([],0,0,.02),
  stationary_high: burst([],0,0,.15),
};
async function vad(mode) {
  const {instance}=await WebAssembly.instantiate(vb), api=instance.exports; api._initialize();
  const handle=api.fvad_new(); if (!handle || api.fvad_set_mode(handle,mode)!==0 || api.fvad_set_sample_rate(handle,48000)!==0) throw Error('setup');
  const ptr=api.malloc(960); if(!ptr) throw Error('malloc');
  return {process(frame) {const pcm=new Int16Array(api.memory.buffer,ptr,480); for(let i=0;i<480;i++){const x=Math.max(-1,Math.min(1,frame[i]));pcm[i]=x<0?x*32768:x*32767;} const r=api.fvad_process(handle,ptr,480);if(r<0)throw Error('process');return r===1;}, dispose(){api.free(ptr);api.fvad_free(handle);}};
}
function stats(flags){let positive=0, streak=0, onset=0;for(const x of flags){if(x){positive++;streak++;if(streak===3)onset++;}else streak=0;}return {positive,onset};}
const rows=[];
for(const [name,input] of Object.entries(inputs)) {
  const row={name};
  for(let mode=0;mode<4;mode++){
    const direct=await vad(mode), raw=[];
    for(let i=0;i<input.length;i+=480)raw.push(direct.process(input.subarray(i,i+480)));
    direct.dispose();
    const denoised=await vad(mode), flags=[]; let failed=false;
    const meter=await createNoiseMeter(rb,48000,{vad:denoised,onAnalysis:f=>flags.push(f.speech==='speech'),onFailure:()=>{failed=true;}});
    meter.push(input); meter.dispose(); if(failed||flags.length!==399)throw Error('analysis failed');
    row[mode]={raw:stats(raw),rnnoise:stats(flags)};
  }
  rows.push(row);
}
console.log(JSON.stringify(rows,null,2));
