const fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),{webcrypto}=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const web=path.join(root,'apps/client/web/prosody');
const model=path.join(root,'.local/asr-spike');
const base='https://local.test/prosody/';
const messages=[],requests=[];
let context;
const sandbox={console,URL,TextDecoder,TextEncoder,Uint8Array,Int8Array,Int16Array,Uint16Array,Int32Array,Uint32Array,Float32Array,Float64Array,ArrayBuffer,DataView,WebAssembly,performance,crypto:webcrypto,setTimeout,clearTimeout,Response,WorkerGlobalScope:function(){},location:{href:base+'asr-worker.js'},postMessage:x=>messages.push(x),
 fetch:async(url,options={})=>{url=String(url);requests.push({url,method:options.method||'GET'});let file;if(url.startsWith(base))file=path.join(web,url.slice(base.length));else if(url.startsWith('https://huggingface.co/k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16/resolve/ba6078bca4daf3f0dd37f79d0ab505af71df14a6/'))file=path.join(model,url.split('/').at(-1));else throw Error('Unexpected URL '+url);return new Response(fs.readFileSync(file),{headers:{'Content-Type':url.endsWith('.wasm')?'application/wasm':'application/octet-stream'}});},
 importScripts:(...urls)=>{for(const u of urls)vm.runInContext(fs.readFileSync(path.join(web,u),'utf8'),context,{filename:u});}
};sandbox.self=sandbox;
context=vm.createContext(sandbox);
function wave(i){const raw=fs.readFileSync(path.join(model,`test_wavs/${i}.wav`));let rate,channels,bits,pcm;for(let at=12;at+8<=raw.length;){const kind=raw.toString('ascii',at,at+4),size=raw.readUInt32LE(at+4);if(kind==='fmt '){channels=raw.readUInt16LE(at+10);rate=raw.readUInt32LE(at+12);bits=raw.readUInt16LE(at+22);}if(kind==='data')pcm=raw.subarray(at+8,at+8+size);at+=8+size+(size%2);}if(channels!==1||bits!==16)throw Error('Unexpected WAV');return{sampleRate:rate,samples:Float32Array.from({length:pcm.length/2},(_,j)=>pcm.readInt16LE(j*2)/32768)};}
(async()=>{
 vm.runInContext(fs.readFileSync(path.join(web,'asr-worker.js'),'utf8'),context,{filename:'asr-worker.js'});
 const begin=performance.now();await sandbox.onmessage({data:{type:'init'}});const initMs=performance.now()-begin;
 if(!messages.some(x=>x.type==='ready'))throw Error('Worker never ready: '+JSON.stringify(messages));
 const outputs=[];let sequence=0;
 for(let i=0;i<4;i++){
  const w=wave(i),start=messages.length,t=performance.now(),chunk=Math.round(w.sampleRate*.16);
  for(let at=0;at<w.samples.length;at+=chunk)await sandbox.onmessage({data:{type:'audio',samples:w.samples.slice(at,at+chunk),sampleRate:w.sampleRate,sequence:sequence++}});
  for(let j=0;j<14;j++)await sandbox.onmessage({data:{type:'audio',samples:new Float32Array(chunk),sampleRate:w.sampleRate,sequence:sequence++}});
  const result=messages.slice(start);outputs.push({sample:i,processingMs:performance.now()-t,endpoints:result.filter(x=>x.endpoint),lastNonempty:result.filter(x=>x.text).at(-1),errors:result.filter(x=>x.type==='error')});
 }
 if(outputs.some(x=>x.errors.length||!x.endpoints.length))throw Error('Fixture failed or endpoint missing');
 const countBeforeInvalid=messages.length;
 await sandbox.onmessage({data:{type:'audio',samples:new Float32Array(1),sampleRate:16000,sequence:0}});
 if(!messages.slice(countBeforeInvalid).some(x=>x.type==='error'))throw Error('Invalid sequence accepted');
 const report={kind:'actual application classic worker in Node VM with official browser WASM; not actual browser/microphone',initMs,requests,outputs,invalidSequence:messages.slice(countBeforeInvalid),peakRssKiB:process.resourceUsage().maxRSS};
 fs.writeFileSync(path.join(__dirname,'evidence/application-worker-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
})().catch(error=>{console.error(error);process.exitCode=1});
