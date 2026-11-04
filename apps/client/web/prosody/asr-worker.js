// Classic worker. Only immutable public model files leave this origin as GETs.
// PCM is processed in this worker; scripts never need to be sent here.
importScripts('./vendor/sherpa/sherpa-onnx-wasm-web.js','./vendor/sherpa/sherpa-onnx-asr.js');
const BASE='https://huggingface.co/k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16/resolve/ba6078bca4daf3f0dd37f79d0ab505af71df14a6/';
const ASSETS=[
 ['encoder-epoch-99-avg-1.int8.onnx',126968852,'8d0b1aa24fbedd4e3948564ab7facd151b8ce9b0c48fc987c541de2de3af5697'],
 ['decoder-epoch-99-avg-1.onnx',11309084,'b29cfb4575141e50a30a22b2c4579934f3d4f45b83c9c8c08c3aef5a3fa7abfc'],
 ['joiner-epoch-99-avg-1.int8.onnx',2581421,'128b80a66a1f718488af8560f9d15895109b99ff3e573f0a0130e03774ef1ced'],
 ['tokens.txt',60246,'016bdf0965029263b7ad01b742366ee542ef0bef38261510e8176ff6f2e9e668'],
];
const TOTAL=ASSETS.reduce((n,a)=>n+a[1],0);
let recognizer=null,stream=null,loading=false,lastSequence=-1;
async function initialize(){
  if(loading||recognizer)throw Error('Already initialized');loading=true;
  const module=await SherpaOnnx({locateFile:name=>new URL('./vendor/sherpa/'+name,self.location.href).href});
  let loaded=0;
  for(const [name,size,sha] of ASSETS){
    const response=await fetch(BASE+name,{credentials:'omit',cache:'force-cache',referrerPolicy:'no-referrer'});
    if(!response.ok)throw Error('Model download failed');
    const bytes=new Uint8Array(size),reader=response.body?.getReader();
    if(!reader)throw Error('Streaming download unavailable');
    let offset=0;
    while(true){
      const {done,value}=await reader.read();if(done)break;
      if(offset+value.length>size){await reader.cancel();throw Error('Model size mismatch');}
      bytes.set(value,offset);offset+=value.length;postMessage({type:'progress',loaded:loaded+offset,total:TOTAL});
    }
    if(offset!==size)throw Error('Model size mismatch');
    const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
    if(hash!==sha)throw Error('Model integrity mismatch');
    module.FS.writeFile('/'+name,bytes);loaded+=size;postMessage({type:'progress',loaded,total:TOTAL});
  }
  recognizer=createOnlineRecognizer(module,{featConfig:{sampleRate:16000,featureDim:80},modelConfig:{
    transducer:{encoder:'/'+ASSETS[0][0],decoder:'/'+ASSETS[1][0],joiner:'/'+ASSETS[2][0]},
    tokens:'/tokens.txt',numThreads:1,provider:'cpu'},decodingMethod:'greedy_search',enableEndpoint:1});
  if(!recognizer.handle)throw Error('Recognizer creation failed');
  for(const [name] of ASSETS)module.FS.unlink('/'+name);
  stream=recognizer.createStream();loading=false;postMessage({type:'ready'});
}
self.onmessage=async({data})=>{
  try{
    if(data?.type==='init'){await initialize();return;}
    if(data?.type!=='audio'||!recognizer||!stream)throw Error('Recognizer not ready');
    const {samples,sampleRate,sequence}=data;
    if(!(samples instanceof Float32Array)||samples.length===0||samples.length>19200||samples.some(x=>!Number.isFinite(x))
      ||!Number.isFinite(sampleRate)||sampleRate<8000||sampleRate>96000||!Number.isSafeInteger(sequence)||sequence<=lastSequence)
      throw Error('Invalid audio chunk');
    lastSequence=sequence;
    stream.acceptWaveform(sampleRate,samples);
    while(recognizer.isReady(stream))recognizer.decode(stream);
    const result=recognizer.getResult(stream),endpoint=recognizer.isEndpoint(stream);
    postMessage({type:'result',sequence,text:result.text||'',endpoint});
    if(endpoint)recognizer.reset(stream);
  }catch{postMessage({type:'error',message:'기기 안 음성 인식을 계속할 수 없어요. 다시 준비하거나 위치 표시를 꺼 주세요.'});}
};
