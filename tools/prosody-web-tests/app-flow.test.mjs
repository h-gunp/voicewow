import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// Test real event handlers and acoustic analysis. Only browser UI/audio decoding
// and TTS worker transport are stand-ins; no microphone or model is downloaded.
class Element {
  constructor(id='') {
    Object.assign(this,{id,value:'',textContent:'',hidden:false,disabled:false,dataset:{},style:{},children:[],listeners:{},attributes:{},clientWidth:480});
    const classes=new Set();this.classList={add:(x)=>classes.add(x),remove:(x)=>classes.delete(x),toggle:(x,on)=>on?classes.add(x):classes.delete(x)};
    this.lines=0;this.strokes=[];this.marks=[];let pathPoints=0;const self=this;
    this.context=new Proxy({}, {get:(target,key)=>target[key]??((...args)=>{
      if(key==='beginPath')pathPoints=0;
      if(key==='lineTo'){self.lines++;pathPoints++;}
      if(key==='stroke')self.strokes.push({color:target.strokeStyle,points:pathPoints});
      if(key==='arc')self.marks.push({color:target.fillStyle,arguments:args});
    }),set:(t,k,v)=>(t[k]=v,true)});
  }
  addEventListener(name,listener){(this.listeners[name]??=[]).push(listener);}
  removeEventListener(name,listener){this.listeners[name]=(this.listeners[name]||[]).filter(fn=>fn!==listener);}
  removeAttribute(name){delete this.attributes[name];}
  async fire(name,details={}){const event={target:this,preventDefault(){this.defaultPrevented=true;},...details};for(const listener of this.listeners[name]||[])await listener(event);}
  setAttribute(name,value){this.attributes[name]=value;}
  append(...children){this.children.push(...children);}
  replaceChildren(...children){this.children=[...children];}
  querySelectorAll(){return this.children;}
  set innerHTML(value){this.children=[];this.html=value;}
  getContext(){return this.context;}
  getBoundingClientRect(){return {left:0,top:0,width:480,height:278};}
  scrollIntoView(){}
  focus(){}
}

function voicePayload(){
  const payload=new Float32Array(24000);let phase=0;
  for(let i=0;i<payload.length;i++){phase+=2*Math.PI*(200+35*Math.sin(i/16000*4))/16000;payload[i]=.2*Math.sin(phase);}
  return payload;
}
async function settle(predicate){
  for(let i=0;i<100;i++){if(predicate())return;await new Promise(resolve=>setTimeout(resolve,10));}
  assert.fail('UI operation did not settle');
}

async function setup({microphone=false, holdResume=false, holdPermission=false, rejectResume=false}={}){
  const html=await readFile(new URL('../../apps/client/web/prosody/index.html',import.meta.url),'utf8');
  const elements=new Map([...html.matchAll(/id="([^"]+)"/g)].map(m=>[m[1],new Element(m[1])]));
  const groups={};
  for(const name of ['mode','practice-tab','result-tab','flow-step']){
    const key=name.replace(/-([a-z])/g,(_,c)=>c.toUpperCase());
    groups[name]=[...html.matchAll(new RegExp(`data-${name}="([^"]+)"`,'g'))].map(m=>{const e=new Element();e.dataset[key]=m[1];return e;});
  }
  const practice=new Element(),coverage=new Element(),windowEvents={},documentEvents={},workers=[],playedAudio=[];
  const body=new Element();
  const document={body,hidden:false,getElementById:id=>elements.get(id),createElement:()=>new Element(),
    querySelector:selector=>selector==='.practice'?practice:coverage,
    querySelectorAll:selector=>selector.split(',').flatMap(s=>{const list=groups[s.trim().slice(6,-1)]||[];return s==='[data-flow-step]'&&body.dataset.flowStep!==undefined?[body,...list]:list;}),
    addEventListener:(name,fn)=>{documentEvents[name]=fn;}};
  const original={location:globalThis.location,window:globalThis.window,document:globalThis.document,Worker:globalThis.Worker,Audio:globalThis.Audio,MediaRecorder:globalThis.MediaRecorder};
  const navigatorDescriptor=Object.getOwnPropertyDescriptor(globalThis,'navigator');
  let microphoneRequests=0,liveVoice=true,trackStopped=false,liveReads=0,contextOpens=0, resumeStarted=false, releaseResume;
  const resumeGate=new Promise(resolve=>{releaseResume=resolve;});
  let releasePermission;const permissionGate=new Promise(resolve=>{releasePermission=resolve;});
  const track={stop(){trackStopped=true;},addEventListener(){}};
  const stream={getTracks:()=>[track],getAudioTracks:()=>[track]};
  Object.defineProperty(globalThis,'navigator',{configurable:true,value:{mediaDevices:{async getUserMedia(){
    microphoneRequests++;
    if(microphone){if(holdPermission)await permissionGate;return stream;}
    const error=new Error('Test microphone permission denied');error.name='NotAllowedError';throw error;
  }}}});
  globalThis.document=document;
  globalThis.location={origin:'https://voicemate.test',search:''};
  globalThis.Worker=class {
    constructor(){this.requests=[];this.terminated=false;workers.push(this);}
    postMessage(message){this.requests.push(message);}
    terminate(){this.terminated=true;}
    emit(data){this.onmessage?.({data});}
  };
  globalThis.Audio=class {
    constructor(url){Object.assign(this,{url,currentTime:0,playedAt:null,paused:false,listeners:{}});playedAudio.push(this);}
    addEventListener(name,listener){this.listeners[name]=listener;}
    load(){this.listeners.loadedmetadata?.();}
    async play(){this.playedAt=this.currentTime;}
    pause(){this.paused=true;}
  };
  const FakeRecorder=class {
    constructor(){this.state='inactive';this.mimeType='application/test-audio';this.listeners={};}
    addEventListener(name,listener){(this.listeners[name]??=[]).push(listener);}
  removeEventListener(name,listener){this.listeners[name]=(this.listeners[name]||[]).filter(fn=>fn!==listener);}
  removeAttribute(name){delete this.attributes[name];}
    start(){this.state='recording';}
    stop(){
      if(this.state==='inactive')return;
      this.state='inactive';
      for(const listener of this.listeners.dataavailable||[])listener({data:new Blob([voicePayload().buffer],{type:this.mimeType})});
      for(const listener of this.listeners.stop||[])listener();
    }
  };
  globalThis.MediaRecorder=FakeRecorder;
  globalThis.window={innerWidth:1000,MediaRecorder:FakeRecorder,AudioContext:class {
    constructor(){contextOpens++;this.sampleRate=48000;this.state='suspended';}
    async resume(){resumeStarted=true;if(holdResume)await resumeGate;if(rejectResume)throw new Error('resume failed');if(this.state!=='closed')this.state='running';}
    createMediaStreamSource(){return {connect(){},disconnect(){}};}
    createAnalyser(){return {fftSize:4096,disconnect(){},getFloatTimeDomainData(array){
      liveReads++;
      for(let i=0;i<array.length;i++)array[i]=liveVoice ? .2*Math.sin(2*Math.PI*220*i/48000) : 0;
    }};}
    async decodeAudioData(bytes){const samples=new Float32Array(bytes);return {duration:samples.length/16000,length:samples.length,numberOfChannels:1,sampleRate:16000,getChannelData:()=>samples};}
    async close(){this.state='closed';}
  },speechSynthesis:{getVoices:()=>[],addEventListener(){},cancel(){}},addEventListener:(name,fn)=>{windowEvents[name]=fn;}};
  globalThis.window.parent={};
  const el=id=>elements.get(id),button=(group,value)=>groups[group].find(e=>Object.values(e.dataset).includes(value));
  const audio=new Blob([voicePayload().buffer],{type:'application/test-audio'});audio.name='test-reference.wav';
  await import(`../../apps/client/web/prosody/app.js?flow=${Date.now()}-${Math.random()}`);
  return {el,button,workers,playedAudio,html,
    async inputAudio(id,file=audio){el(id).files=[file];await el(id).fire('change');},
    microphoneRequests:()=>microphoneRequests,
    contextOpens:()=>contextOpens,
    liveReads:()=>liveReads,
    setLiveVoice(value){liveVoice=Boolean(value);},
    trackStopped:()=>trackStopped,
    resumeStarted:()=>resumeStarted, releaseResume, releasePermission,
    resize(){windowEvents.resize?.();},
    message(event){windowEvents.message?.(event);},
    hostCleanup(){window.voiceMateProsodyCleanup();},
    async prepareScript(){await button('mode','script').fire('click');el('script-input').value='안녕하세요. 잠시 말씀드릴게요.';await el('apply-script').fire('click');},
    hide(){document.hidden=true;documentEvents.visibilitychange?.();},
    cleanup(){windowEvents.pagehide?.();for(const [key,value] of Object.entries(original)){if(value===undefined)delete globalThis[key];else globalThis[key]=value;}if(navigatorDescriptor)Object.defineProperty(globalThis,'navigator',navigatorDescriptor);else delete globalThis.navigator;},
  };
}

test('reference practice keeps per-sentence guides and chosen segments without grades',async()=>{
  const ui=await setup(),{el,button,inputAudio}=ui;
  try{
    await ui.prepareScript();
    assert.equal(el('goal-target'),undefined,'standalone pitch goals must not remain in the app flow');
    assert.equal(el('goal-region'),undefined);
    assert.equal(el('script-sentence-select').children.length,2);
    assert.equal(el('phrase-text').textContent,'안녕하세요.');
    assert.equal(el('record').disabled,true,'example practice must have a reference before recording');
    assert.equal(el('user-file').disabled,true);
    await inputAudio('reference-file');await settle(()=>el('reference-status').textContent.includes('연결한 파일'));
    assert.equal(el('record').disabled,false);
    await inputAudio('user-file');await settle(()=>el('feedback-list').children.length===3);
    assert.equal(el('pitch-score'),undefined);
    assert.equal(el('volume-score'),undefined);
    const measurementDetails=ui.html.match(/<details\b[^>]*id="measurement-details"[^>]*>[\s\S]*?<\/details>/)?.[0];
    assert.ok(measurementDetails,'detailed measurements remain available behind the existing disclosure');
    for(const id of ['feedback-summary','summary-observation','coaching-note']){
      assert.match(measurementDetails,new RegExp(`id="${id}"`),
        'fine-grained differences belong in measurement details, not the main practice feedback');
    }
    const mainCoaching=ui.html.match(/<div\b[^>]*id="practice-coaching"[^>]*>[\s\S]*?<\/div>/)?.[0]||'';
    assert.doesNotMatch(mainCoaching,/id="(?:summary-observation|coaching-note)"/,
      'the main coaching surface must not foreground the detailed measurement block');
    for(const card of el('feedback-list').children){
      const displayed=card.children.map(child=>child.textContent).join(' ');
      assert.doesNotMatch(displayed,/\d+(?:\.\d+)?\s*(?:반음|dB)|점수|합격|불합격/,
        'region cards should help choose practice, rather than display an error grade');
    }
    assert.match(el('summary-observation').textContent,/0.0반음 차이/);
    assert.equal(el('practice-coaching').hidden,false);
    assert.match(el('coaching-title').textContent+' '+el('coaching-observation').textContent,/파란 예시도 같은 쪽/,
      'identical recordings should acknowledge the matching endpoint direction');
    assert.doesNotMatch(el('coaching-observation').textContent,/\d+(?:\.\d+)?\s*(?:반음|dB)|전체.*(?:성공|잘|정확)|자연스럽|정상/,
      'endpoint agreement is not a judgement about whole-utterance quality');
    assert.match(el('coaching-action').textContent,/다음|이어서|유지|똑같이|지금.*변화/,
      'matching direction should support continuing practice without demanding an exact imitation');
    assert.doesNotMatch(el('coaching-action').textContent,/들어야|듣고|들으며/,
      'understanding practice guidance must not require listening');
    assert.equal(el('reference-segment-play').hidden,false);
    assert.equal(el('reference-segment-play').disabled,false);
    assert.equal(el('graph-selected-label').textContent,'앞부분 선택됨');
    await el('feedback-list').children[2].fire('click');
    await button('result-tab','volume').fire('click');
    assert.equal(el('graph-selected-label').textContent,'끝부분 선택됨','tab switch must preserve the chosen region');
    assert.match(el('summary-observation').textContent,/0.0dB 차이/);
    assert.equal(el('segment-play').disabled,false);
    await button('result-tab','duration').fire('click');
    assert.equal(el('duration-panel').hidden,false);
    assert.equal(el('practice-coaching').hidden,true);
    await button('result-tab','pitch').fire('click');
    assert.equal(el('graph-selected-label').textContent,'끝부분 선택됨');
    assert.doesNotMatch(el('result-detail').textContent,/합격|50점|100점|시험용 기준/);
    await el('sentence-next').fire('click');
    assert.equal(el('phrase-text').textContent,'잠시 말씀드릴게요.');
    assert.equal(el('remove-reference').hidden,true);
    assert.equal(el('record').disabled,true,'the previous sentence reference must not leak into the next sentence');
    await el('sentence-prev').fire('click');
    assert.equal(el('remove-reference').hidden,false);
    assert.equal(el('record').disabled,false);
    await el('remove-reference').fire('click');
    assert.equal(el('record').disabled,true);
    assert.equal(el('guide-preview').disabled,true);
  }finally{ui.cleanup();}
});

test('one guide action prepares every sentence on one reused worker and navigation needs no new synthesis',async()=>{
  const ui=await setup(),{el}=ui;
  try{
    await ui.prepareScript();
    const generation=el('generate-guide').fire('click');
    await settle(()=>ui.workers.length===1);
    const worker=ui.workers[0],first=worker.requests[0];
    assert.equal(first.text,'안녕하세요.');
    assert.equal(el('record').disabled,true);
    worker.emit({type:'progress',id:first.id,message:'시험 음성을 준비하고 있어요.'});
    assert.match(el('generation-status').textContent,/시험 음성/);
    worker.emit({type:'complete',id:first.id,samples:voicePayload(),sampleRate:16000});
    await settle(()=>worker.requests.length===2);
    const second=worker.requests[1];
    assert.equal(second.text,'잠시 말씀드릴게요.');
    assert.match(el('guide-ready-count').textContent,/1 \/ 2/);
    assert.match(el('cancel-guide').textContent,/준비된 문장 연습/);
    worker.emit({type:'complete',id:second.id,samples:voicePayload(),sampleRate:16000});
    await generation;
    assert.equal(ui.workers.length,1,'the expensive model/worker is reused across sentences');
    assert.match(el('guide-ready-count').textContent,/2 \/ 2/);
    assert.equal(el('generate-guide').disabled,true);
    assert.equal(el('record').disabled,false);
    await el('sentence-next').fire('click');
    assert.equal(el('phrase-text').textContent,'잠시 말씀드릴게요.');
    assert.equal(el('record').disabled,false,'next sentence already has its own audio and measured guide');
    assert.match(el('guide-source').textContent,/AI 가이드/);
    assert.equal(worker.requests.length,2);
    await el('generate-guide').fire('click');
    assert.equal(worker.requests.length,2,'a synthetic click cannot regenerate completed guides');
  }finally{ui.cleanup();}
});

test('partial preparation survives cancellation and retries only the missing sentence after a failure',async()=>{
  const ui=await setup(),{el}=ui;
  try{
    await ui.prepareScript();
    const generation=el('generate-guide').fire('click');
    await settle(()=>ui.workers.length===1);
    const worker=ui.workers[0],first=worker.requests[0];
    worker.emit({type:'complete',id:first.id,samples:voicePayload(),sampleRate:16000});
    await settle(()=>worker.requests.length===2);
    const stale=worker.requests[1];
    await el('cancel-guide').fire('click');await generation;
    assert.equal(worker.terminated,true);
    assert.equal(el('record').disabled,false);
    assert.match(el('guide-ready-count').textContent,/1 \/ 2/);
    worker.emit({type:'complete',id:stale.id,samples:voicePayload(),sampleRate:16000});
    assert.match(el('guide-ready-count').textContent,/1 \/ 2/);
    const retry=el('generate-guide').fire('click');
    await settle(()=>ui.workers.length===2);
    const next=ui.workers[1],request=next.requests[0];
    assert.equal(request.text,'잠시 말씀드릴게요.');
    next.emit({type:'error',id:request.id,message:'모델 파일을 읽지 못했어요.'});
    await retry;
    assert.equal(el('record').disabled,false,'a failure elsewhere cannot discard the ready first guide');
    assert.match(el('generation-status').textContent,/모델 파일/);
    assert.equal(el('generate-guide').disabled,false);
    const resume=el('generate-guide').fire('click');
    await settle(()=>ui.workers.length===3);
    const last=ui.workers[2],lastRequest=last.requests[0];
    assert.equal(lastRequest.text,'잠시 말씀드릴게요.');
    last.emit({type:'complete',id:lastRequest.id,samples:voicePayload(),sampleRate:16000});
    await resume;
    assert.match(el('guide-ready-count').textContent,/2 \/ 2/);
    await el('sentence-next').fire('click');assert.equal(el('record').disabled,false);
  }finally{ui.cleanup();}
});

test('a failed sentence does not prevent later sentences from becoming ready',async()=>{
  const ui=await setup(),{el}=ui;
  try{
    await ui.prepareScript();
    const generation=el('generate-guide').fire('click');await settle(()=>ui.workers.length===1);
    const first=ui.workers[0];
    first.emit({type:'complete',id:first.requests[0].id,samples:new Float32Array(16000),sampleRate:16000});
    await settle(()=>first.requests.length===2);
    first.emit({type:'complete',id:first.requests[1].id,samples:voicePayload(),sampleRate:16000});
    await generation;
    assert.match(el('guide-ready-count').textContent,/1 \/ 2/);
    assert.match(el('generation-status').textContent,/1번.*다시 준비/);
    assert.equal(el('phrase-text').textContent,'잠시 말씀드릴게요.','partial success selects a ready sentence for practice');
    assert.equal(el('record').disabled,false);
    assert.match(el('sentence-list').children[0].children[2].textContent,/다시 준비/);
  }finally{ui.cleanup();}
});

test('batch preparation reuses uploaded guides and preserves their accepted recording',async()=>{
  const ui=await setup(),{el,inputAudio,button}=ui;
  try{
    await ui.prepareScript();await inputAudio('reference-file');await settle(()=>!el('record').disabled);
    await inputAudio('user-file');await settle(()=>el('result-badge').textContent==='내 녹음');
    const before=el('summary-observation').textContent;
    await button('flow-step','0').fire('click');
    const generation=el('generate-guide').fire('click');await settle(()=>ui.workers.length===1);
    const worker=ui.workers[0],request=worker.requests[0];
    assert.equal(request.text,'잠시 말씀드릴게요.');
    worker.emit({type:'complete',id:request.id,samples:voicePayload(),sampleRate:16000});await generation;
    assert.match(el('reference-status').textContent,/연결한 파일/);
    assert.equal(el('result-badge').textContent,'내 녹음');
    assert.equal(el('summary-observation').textContent,before);
    assert.equal(el('user-play').disabled,false);
  }finally{ui.cleanup();}
});

test('optional regeneration and background cancellation preserve existing completed guides',async()=>{
  const ui=await setup(),{el}=ui;
  try{
    await ui.prepareScript();
    const generation=el('generate-guide').fire('click');await settle(()=>ui.workers.length===1);
    const worker=ui.workers[0];
    worker.emit({type:'complete',id:worker.requests[0].id,samples:voicePayload(),sampleRate:16000});
    await settle(()=>worker.requests.length===2);
    ui.hide();await generation;
    assert.equal(worker.terminated,true);
    assert.match(el('generation-status').textContent,/화면을 벗어나/);
    assert.equal(el('record').disabled,false);
    const regenerate=el('regenerate-guide').fire('click');await settle(()=>ui.workers.length===2);
    const next=ui.workers[1],request=next.requests[0];
    assert.equal(request.text,'안녕하세요.');
    await el('cancel-guide').fire('click');await regenerate;
    assert.equal(next.terminated,true);
    assert.equal(el('record').disabled,false);
    assert.match(el('guide-ready-count').textContent,/1 \/ 2/);
    next.emit({type:'complete',id:request.id,samples:new Float32Array(1),sampleRate:16000});
    assert.equal(el('record').disabled,false);
    const replacement=el('regenerate-guide').fire('click');await settle(()=>ui.workers.length===3);
    const failed=ui.workers[2];
    failed.emit({type:'error',id:failed.requests[0].id,message:'새 음성을 준비하지 못했어요.'});await replacement;
    assert.equal(el('record').disabled,false);
    assert.match(el('generation-status').textContent,/이전 가이드는 그대로/);
  }finally{ui.cleanup();}
});

test('failed replacement recordings keep the previous selected result and playable clip',async()=>{
  const ui=await setup(),{el,button,inputAudio}=ui;
  try{
    await ui.prepareScript();
    await inputAudio('reference-file');await settle(()=>el('reference-status').textContent.includes('연결한 파일'));
    await inputAudio('user-file');await settle(()=>el('feedback-list').children.length===3);
    await el('feedback-list').children[2].fire('click');
    const previous={badge:el('result-badge').textContent,selected:el('graph-selected-label').textContent,
      observation:el('summary-observation').textContent,action:el('coaching-action').textContent};
    const assertRetained=()=>{
      assert.equal(el('result-badge').textContent,previous.badge);
      assert.equal(el('graph-selected-label').textContent,previous.selected);
      assert.equal(el('summary-observation').textContent,previous.observation);
      assert.equal(el('coaching-action').textContent,previous.action);
      assert.equal(el('user-play').disabled,false,'last successful clip remains playable');
      assert.equal(el('segment-play').disabled,false,'selected interval remains available');
    };

    const silence=new Blob([new Float32Array(24000).buffer],{type:'application/test-audio'});
    await inputAudio('user-file',silence);
    await settle(()=>!el('record').disabled&&/목소리|이전/.test(el('result-status').textContent));
    assertRetained();
    assert.match(el('result-status').textContent,/이전|기존/,'failure explains the retained result');

    // A malformed file exercises decode failure, rather than low-voice analysis.
    await inputAudio('user-file',new Blob([new Uint8Array([1,2,3])],{type:'application/test-audio'}));
    await settle(()=>!el('record').disabled&&/이전|기존/.test(el('result-status').textContent));
    assertRetained();

    await el('record').fire('click');
    assert.equal(ui.microphoneRequests(),1,'permission denial must reach getUserMedia');
    assertRetained();
    assert.match(el('practice-status').textContent,/허용되지|권한/);
  }finally{ui.cleanup();}
});

test('an unusable reference replacement preserves both the guide and the previous recording',async()=>{
  const ui=await setup(),{el,inputAudio}=ui;
  try{
    await ui.prepareScript();
    await inputAudio('reference-file');await settle(()=>el('reference-status').textContent.includes('연결한 파일'));
    await inputAudio('user-file');await settle(()=>el('feedback-list').children.length===3);
    await el('feedback-list').children[1].fire('click');
    const selected=el('graph-selected-label').textContent,observation=el('summary-observation').textContent;
    const silence=new Blob([new Float32Array(24000).buffer],{type:'application/test-audio'});silence.name='silent-reference.wav';
    await inputAudio('reference-file',silence);
    await settle(()=>!el('record').disabled&&/기존|이전/.test(el('reference-status').textContent));
    assert.equal(el('remove-reference').hidden,false,'the usable reference remains connected');
    assert.equal(el('guide-preview').disabled,false);
    assert.equal(el('graph-selected-label').textContent,selected);
    assert.equal(el('summary-observation').textContent,observation);
    assert.equal(el('user-play').disabled,false);
  }finally{ui.cleanup();}
});

test('a successful replacement updates the recording only after analysis completes',async()=>{
  const ui=await setup(),{el,inputAudio}=ui;
  try{
    await ui.prepareScript();
    await inputAudio('reference-file');await settle(()=>el('reference-status').textContent.includes('연결한 파일'));
    await inputAudio('user-file');await settle(()=>el('feedback-list').children.length===3);
    const before=el('summary-observation').textContent;
    assert.match(before,/0.0반음 차이/);
    const samples=voicePayload();
    // Change contour shape, not merely speaker pitch, which is normalized out.
    let phase=0;
    for(let i=0;i<samples.length;i++){
      const t=i/16000;phase+=2*Math.PI*(190+65*Math.sin(t*8))/16000;samples[i]=.2*Math.sin(phase);
    }
    await inputAudio('user-file',new Blob([samples.buffer],{type:'application/test-audio'}));
    await settle(()=>!el('record').disabled&&el('summary-observation').textContent!==before);
    assert.equal(el('user-play').disabled,false);
    assert.equal(el('feedback-list').children.length,3);
    assert.notEqual(el('summary-observation').textContent,before);
  }finally{ui.cleanup();}
});

test('region playback keeps short words whole and retry keeps the full sentence reference',async()=>{
  const ui=await setup(),{el,button,inputAudio}=ui;
  try{
    await ui.prepareScript();
    await inputAudio('reference-file');await settle(()=>el('reference-status').textContent.includes('연결한 파일'));
    await inputAudio('user-file');await settle(()=>el('feedback-list').children.length===3);
    await el('feedback-list').children[1].fire('click');
    const selectedLabel=el('graph-selected-label').textContent;
    await el('segment-play').fire('click');
    await settle(()=>ui.playedAudio.at(-1)?.playedAt!==null);
    assert.equal(ui.playedAudio.at(-1).playedAt,0,'short original recordings are not cut at arbitrary syllable positions');
    assert.match(el('playback-range-info').textContent,/전체를 재생/);
    assert.match(el('listening-status').textContent,/내 녹음.*전체/);
    assert.match(el('region-boundary-note').textContent,/특정 글자나 단어를 인식한 위치는 아니/);
    assert.equal(el('result-phrase-text').textContent,'안녕하세요.');
    assert.equal(el('repeat-region').disabled,false);
    await el('repeat-region').fire('click');
    assert.equal(el('phrase-text').textContent,'안녕하세요.');
    assert.equal(el('user-play').disabled,false,'retry preserves the accepted recording until a new analysis succeeds');
    assert.equal(el('graph-selected-label').textContent,selectedLabel);
    assert.match(el('practice-status').textContent,/전체를 다시 읽어/);
    await el('guide-play').fire('click');await settle(()=>ui.playedAudio.at(-1)?.playedAt!==null);
    assert.equal(ui.playedAudio.at(-1).playedAt,0,'the repeat guide remains the complete sentence');
    await el('next-sentence-result').fire('click');
    assert.equal(el('phrase-text').textContent,'잠시 말씀드릴게요.');
    assert.equal(el('record').disabled,true,'references remain isolated by sentence');
  }finally{ui.cleanup();}
});

test('sentence queue exposes each text unit and edited drafts cannot use stale guides',async()=>{
  const ui=await setup(),{el,button,inputAudio}=ui;
  try{
    assert.ok(ui.html.indexOf('class="mode-tabs')<ui.html.indexOf('class="practice-steps'));
    await button('mode','script').fire('click');
    const original='오늘은 함께 연습할 목소리의 높낮이를 살펴보겠습니다. 편안한 속도로 읽어 주세요. '+ '긴 대본을 짧은 문장으로 나누면 한 번에 읽을 양이 줄어듭니다, '.repeat(4);
    el('script-input').value=original;await el('apply-script').fire('click');
    assert.ok(el('sentence-list').children.length>2);
    assert.ok(el('sentence-list').children.every(item=>Array.from(item.children[1].textContent).length<=60));
    assert.equal(el('sentence-current-text').textContent,'오늘은 함께 연습할 목소리의 높낮이를 살펴보겠습니다.');
    await el('sentence-list').children[1].fire('click');
    assert.equal(el('sentence-current-text').textContent,'편안한 속도로 읽어 주세요.');
    await inputAudio('reference-file');await settle(()=>!el('record').disabled);
    await inputAudio('user-file');await settle(()=>el('result-badge').textContent==='내 녹음');
    el('script-input').value='다른 문장으로 바꿉니다.';await el('script-input').fire('input');
    assert.equal(el('script-draft-warning').hidden,false);
    assert.equal(el('record').disabled,true);
    assert.equal(el('generate-guide').disabled,true);
    assert.equal(el('reference-file').disabled,true);
    assert.equal(el('remove-reference').disabled,true);
    await inputAudio('reference-file');
    assert.equal(el('result-badge').textContent,'내 녹음','a reference-file event cannot overwrite the accepted result while a new draft is pending');
    await el('apply-script').fire('click');
    assert.equal(el('sentence-list').children.length,1);
    assert.equal(el('sentence-current-text').textContent,'다른 문장으로 바꿉니다.');
    assert.equal(el('record').disabled,true,'a guide for the old script is never attached to edited text');
    assert.equal(el('script-draft-warning').hidden,true);
  }finally{ui.cleanup();}
});

test('host cleanup during the pre-analysis delay cannot open a new audio decoder afterwards',async()=>{
  const ui=await setup(),{el,inputAudio}=ui;
  try{
    await ui.prepareScript();await inputAudio('reference-file');await settle(()=>!el('record').disabled);
    const before=ui.contextOpens();
    await inputAudio('user-file');
    ui.hostCleanup();
    await new Promise(resolve=>setTimeout(resolve,70));
    assert.equal(ui.contextOpens(),before);
    assert.equal(el('record').textContent,'● 녹음 시작');
  }finally{ui.cleanup();}
});

test('same-origin host cleanup stops a live microphone and untrusted messages do not',async()=>{
  const ui=await setup({microphone:true}),{el,inputAudio}=ui;
  try{
    await ui.prepareScript();await inputAudio('reference-file');await settle(()=>!el('record').disabled);
    await el('record').fire('click');await settle(()=>ui.liveReads()>1);
    ui.message({origin:'https://other.test',source:window.parent,data:{type:'voicemate:prosody:cleanup'}});
    assert.equal(ui.trackStopped(),false);
    ui.message({origin:location.origin,source:{},data:{type:'voicemate:prosody:cleanup'}});
    assert.equal(ui.trackStopped(),false);
    ui.message({origin:location.origin,source:window.parent,data:{type:'voicemate:prosody:cleanup'}});
    assert.equal(ui.trackStopped(),true);
    assert.equal(el('record').textContent,'● 녹음 시작');
    ui.hostCleanup();
  }finally{ui.cleanup();}
});

test('repeated DTW matches at a single user timestamp cannot enable excerpt playback',async()=>{
  const ui=await setup(),{el,inputAudio}=ui;
  try{
    el('guide-select').value='sunglasses';await el('guide-select').fire('change');
    const samples=new Float32Array(Math.round(.19*16000));
    for(let i=0;i<samples.length;i++)samples[i]=.2*Math.sin(2*Math.PI*100*i/16000);
    await inputAudio('user-file',new Blob([samples.buffer],{type:'application/test-audio'}));
    await settle(()=>el('feedback-list').classList&&el('result-badge').textContent==='내 녹음');
    assert.equal(el('segment-play').disabled,true);
    assert.match(el('segment-play').textContent,/찾지 못했어요/);
    const count=ui.playedAudio.length;
    await el('segment-play').fire('click');
    assert.equal(ui.playedAudio.length,count,'even a synthetic click on a disabled control cannot play a zero-length range');
  }finally{ui.cleanup();}
});

test('recording shows measured voice live and keeps the completed comparison on the practice graph',async()=>{
  const ui=await setup({microphone:true}),{el,button,inputAudio}=ui;
  const voiceStrokes=()=>el('practice-chart').strokes.filter(stroke=>stroke.color==='#34455e'&&stroke.points>0).length;
  const voiceMarks=()=>el('practice-chart').marks.filter(mark=>mark.color==='#34455e').length;
  try{
    await ui.prepareScript();
    await inputAudio('reference-file');await settle(()=>el('reference-status').textContent.includes('연결한 파일'));
    const before=voiceStrokes()+voiceMarks();
    await el('record').fire('click');
    await settle(()=>ui.liveReads()>=3);
    assert.equal(el('practice-graph-card').dataset.phase,'recording');
    assert.match(el('live-status').textContent,/내 목소리/);
    const voiceStatus=el('live-status').textContent;
    assert.ok(voiceStrokes()+voiceMarks()>before,'detected microphone voice must produce visible voice measurements');
    assert.match(el('practice-view-label').textContent,/실시간|녹음 중|시간/);

    ui.setLiveVoice(false);
    const readAtPause=ui.liveReads();
    await settle(()=>ui.liveReads()>=readAtPause+2);
    assert.notEqual(el('live-status').textContent,voiceStatus,'a pause must update the live signal state');
    assert.doesNotMatch(el('live-status').textContent,/내 목소리.*(?:잡히|확인했|들어오)/,
      'past observations must not be presented as a new voice observation during a pause');

    await el('record').fire('click');
    await settle(()=>el('practice-graph-card').dataset.phase==='result');
    assert.equal(ui.trackStopped(),true,'completed recording releases the microphone');
    assert.equal(el('user-play').disabled,false);
    const after=voiceStrokes()+voiceMarks();
    assert.ok(after>before);
    await button('practice-tab','volume').fire('click');
    assert.ok(voiceStrokes()+voiceMarks()>after,'changing the practice metric must retain the completed user curve');
    const afterTab=voiceStrokes()+voiceMarks();
    ui.resize();
    assert.ok(voiceStrokes()+voiceMarks()>afterTab,'resizing must redraw the user comparison rather than erase it');
    assert.equal(el('practice-graph-card').dataset.phase,'result');
  }finally{ui.cleanup();}
});

test('step pages gate unfinished results, lock during recording and open an accepted result after finishing',async()=>{
  const ui=await setup({microphone:true}),{el,button}=ui;
  try{
    assert.equal(el('flow-prepare').hidden,false);
    assert.equal(el('flow-record').hidden,true);
    assert.equal(button('flow-step','1').disabled,false);
    await button('flow-step','1').fire('click');
    assert.equal(el('flow-record').hidden,false);
    await el('flow-previous').fire('click');
    await el('flow-next').fire('click');
    assert.equal(el('flow-record').hidden,false);
    await button('flow-step','2').fire('click');
    assert.equal(el('flow-results').hidden,true,'an empty result is not an available next page');
    await el('record').fire('click');await settle(()=>ui.liveReads()>1);
    assert.equal(el('flow-previous').disabled,true);
    await el('flow-previous').fire('click');
    assert.equal(el('flow-record').hidden,false);
    await el('record').fire('click');await settle(()=>el('result-badge').textContent==='내 녹음');
    assert.equal(el('flow-results').hidden,false);
    assert.equal(el('flow-record').hidden,true);
    await el('retry').fire('click');
    assert.equal(el('flow-record').hidden,false);
    assert.equal(el('user-play').disabled,false,'returning to record keeps the accepted result');
    await button('mode','script').fire('click');
    assert.equal(el('flow-prepare').hidden,false);
    assert.equal(el('flow-next').disabled,true,'a script requires its own guide before entering recording');
  }finally{ui.cleanup();}
});

for(const action of ['hostCleanup','hide']) test(`${action} immediately releases an acquired microphone while AudioContext resume is pending`,async()=>{
  const ui=await setup({microphone:true,holdResume:true}),{el}=ui;
  let start;
  try {
    start=el('record').fire('click');
    await settle(()=>ui.resumeStarted());
    ui[action]();
    assert.equal(ui.trackStopped(),true,'cleanup must stop the microphone without waiting for resume');
    ui.releaseResume(); await start;
    assert.equal(ui.liveReads(),0,'a cancelled startup must not begin recording');
  } finally { ui.releaseResume(); if(start)await start; ui.cleanup(); }
});

test('hiding a standalone page pauses guide playback even while idle',async()=>{
  const ui=await setup(),{el}=ui;
  try {
    await el('guide-play').fire('click');
    assert.ok(ui.playedAudio.length);
    const audio=ui.playedAudio.at(-1);
    assert.equal(audio.paused,false);
    ui.hide();
    assert.equal(audio.paused,true,'backgrounding must stop guide playback');
  } finally {ui.cleanup();}
});

test('a microphone permission result arriving after cancellation is stopped',async()=>{
  const ui=await setup({microphone:true,holdPermission:true});
  const start=ui.el('record').fire('click');
  try {
    await settle(()=>ui.microphoneRequests()===1);
    ui.hostCleanup();ui.releasePermission();await start;
    assert.equal(ui.trackStopped(),true);
    assert.equal(ui.resumeStarted(),false);
  } finally {ui.releasePermission();await start;ui.cleanup();}
});

test('a failed AudioContext resume releases the microphone and allows retry',async()=>{
  const ui=await setup({microphone:true,rejectResume:true});
  try {
    await ui.el('record').fire('click');
    assert.equal(ui.trackStopped(),true);
    assert.equal(ui.el('record').disabled,false);
  } finally {ui.cleanup();}
});
