import { GUIDES } from './guide-data.js';
import { analyzeAudio, analyzeFrame, trimAnalysis, compareAnalyses } from './audio-analysis.js';
import { alignedTrace, wavBytes, segmentObservation } from './lab-utils.js';
import { drawGraph, graphSegmentAt } from './charts.js';
import { parsePracticeScript, selectLocalKoreanVoice } from './script-utils.js';
import { generateGuide, cancelGuide } from './tts-client.js';
import { describeSegmentPractice, buildPracticeSummary, choosePracticeRegions } from './practice-feedback.js';
import { playbackRange } from './practice-region.js';
import { createLiveView } from './live-view.js';
import { createFlowPager } from './flow-pager.js';
import { runGuideBatch } from './guide-batch.js';
import { createScriptTracking } from './script-tracking-ui.js';

const $=id=>document.getElementById(id);
const scriptTracking=createScriptTracking({document,cancelTts:cancelGuide});
let guide=GUIDES[0],practiceTab='pitch',resultTab='pitch',state='idle',clip=null,result=null,session=null;
let playback=null,playbackTimer=null,previewTimer=null,selectedIndex=0,generation=0;
let practiceMode='guide',scriptLines=[],scriptIndex=0,ttsUtterance=null;
let wholeGuide=null;
let scriptUnits=[],appliedScript='',previewRegions=[];
let pager=null,prepareView='edit';
let guideBatch=null,guideNotice='';
const scriptReferences=new Map(),practicedSentences=new Set();
const guideFailures=new Map();
const field=tab=>tab==='volume'?'relativeDb':'relativePitch';
const isBusy=()=>['requesting','recording','processing','generating','asr-loading'].includes(state);
const setText=(id,text)=>{$(id).textContent=text;};
const draftPending=()=>practiceMode==='script'&&scriptLines.length>0&&$('script-input').value!==appliedScript;
const seconds=value=>`${value.toFixed(2)}초`;
const rangeLabel=range=>`${seconds(range.start)}–${seconds(range.end)}`;
function userPlaybackRange(segment,user){
  if(!segment||segment.pairs<5||!Number.isFinite(segment.userStart)||!Number.isFinite(segment.userEnd)||segment.userEnd<=segment.userStart)return null;
  return playbackRange(user,{start:segment.userStart,end:segment.userEnd});
}

function renderGuideRegions(){
  const box=$('guide-region-key');box.replaceChildren();previewRegions=[];
  if(!guide.analysis){setText('guide-boundary-note','선택한 문장의 가이드를 준비하면 시간 구간이 나타나요.');return;}
  previewRegions=choosePracticeRegions(guide.analysis).regions;
  for(const region of previewRegions){
    const item=document.createElement('div');
    const title=document.createElement('strong');title.textContent=region.label;
    const time=document.createElement('span');time.textContent=rangeLabel(region);
    item.append(title,time);box.append(item);
  }
  setText('guide-boundary-note','위 범위는 소리의 시간을 나눈 거예요. 글자별 위치는 아직 구별하지 않아요.');
}

function stopPlayback(){if(playback){playback.pause();playback=null;}clearTimeout(playbackTimer);playbackTimer=null;if(ttsUtterance){ttsUtterance=null;window.speechSynthesis?.cancel();}$('listening-status').hidden=true;}
function stopPreview(){clearInterval(previewTimer);previewTimer=null;$('guide-preview').textContent='↗ 선 움직임 보기';}
function clearClip(){stopPlayback();if(clip)URL.revokeObjectURL(clip.url);clip=null;}
function refresh(){
  const busy=isBusy();
  $('asr-controls').hidden=practiceMode!=='script';
  $('asr-enabled').disabled=busy;
  $('prepare-asr').disabled=busy||!$('asr-enabled').checked;
  for(const id of ['guide-select','guide-play','guide-preview','user-file','reset','retry'])$(id).disabled=busy;
  for(const id of ['script-input','apply-script','script-sentence-select','reference-file','remove-reference'])$(id).disabled=busy;
  for(const button of document.querySelectorAll('[data-mode]')){button.disabled=busy;button.setAttribute('aria-pressed',String(button.dataset.mode===practiceMode));}
  $('sentence-prev').disabled=busy||scriptIndex===0;$('sentence-next').disabled=busy||scriptIndex>=scriptLines.length-1;
  const pending=draftPending();$('script-draft-warning').hidden=!pending;
  const unprepared=practiceMode==='script'&&(!scriptLines.length||pending);
  const missingGuide=!guide.analysis;
  $('record').disabled=(busy&&state!=='recording')||unprepared||missingGuide;
  $('user-file').disabled=busy||unprepared||missingGuide;
  const ready=scriptReferences.size,total=scriptLines.length,missing=total-ready;
  $('generate-guide').disabled=busy||unprepared||missing===0;
  $('generate-guide').textContent=total>0&&missing===0?'전체 가이드 준비 완료':ready>0?`남은 ${missing}개 가이드 만들기`:'전체 가이드 만들기';
  $('regenerate-guide').hidden=!scriptReferences.get(scriptIndex)?.generated;
  $('regenerate-guide').disabled=busy||unprepared;
  $('cancel-guide').hidden=state!=='generating';
  $('cancel-guide').textContent=ready>0?'멈추고 준비된 문장 연습하기':'생성 취소';
  $('guide-progress').hidden=!total;
  $('guide-progress').max=total||1;$('guide-progress').value=ready;
  setText('guide-ready-count',total?`${ready} / ${total}개 가이드 준비`:'');
  for(const button of $('sentence-list').querySelectorAll('button'))button.disabled=busy||pending;
  $('script-sentence-select').disabled=busy||pending;
  $('reference-file').disabled=busy||pending;
  $('remove-reference').disabled=busy||pending;
  $('sentence-prev').disabled=busy||pending||scriptIndex===0;
  $('sentence-next').disabled=busy||pending||scriptIndex>=scriptLines.length-1;
  $('guide-preview').disabled=busy||!guide.analysis;
  $('guide-play').disabled=busy||unprepared||(!guide.audioUrl&&!selectLocalKoreanVoice(window.speechSynthesis?.getVoices()||[]));
  $('guide-play').textContent=guide.audioUrl?'▷ 예시 듣기':'▷ 기기 음성으로 읽어주기';
  $('record').textContent=state==='recording'?'■ 녹음 마치기':state==='requesting'?'마이크 연결 중…':state==='processing'?'분석 중…':'● 녹음 시작';
  $('user-play').disabled=!clip||busy;
  $('segment-play').disabled=!clip||!result||busy||!userPlaybackRange(result.summary.segments[selectedIndex],result.user);
  $('reference-segment-play').disabled=busy||!result||!guide.audioUrl||!result.summary?.segments[selectedIndex]?.pairs;
  $('repeat-region').hidden=!result||resultTab==='duration'||Boolean(wholeGuide);
  $('repeat-region').disabled=busy||!result||pending;
  $('next-sentence-result').hidden=!result||practiceMode!=='script'||scriptIndex>=scriptLines.length-1;
  $('next-sentence-result').disabled=busy||pending;
  $('leave-region').hidden=!wholeGuide;$('leave-region').disabled=busy;
  $('record-indicator').classList.toggle('recording',state==='recording');
  setText('record-indicator',state==='recording'?'녹음 중':state==='requesting'?'마이크 권한 확인 중':state==='processing'?'기기에서 분석 중':'마이크 대기');
  for(const button of document.querySelectorAll('[data-practice-tab]'))button.setAttribute('aria-pressed',String(button.dataset.practiceTab===practiceTab));
  for(const button of document.querySelectorAll('[data-result-tab]'))button.setAttribute('aria-pressed',String(button.dataset.resultTab===resultTab));
  const scriptContext=practiceMode==='script'&&scriptLines.length>0;
  $('script-reading-context').hidden=!scriptContext;$('script-reading-after').hidden=!scriptContext;
  if(scriptContext){
    setText('reading-position',`전체 ${scriptLines.length}개 중 ${scriptIndex+1}번째 연습 구간`);
    setText('reading-before',scriptLines[scriptIndex-1]||'대본의 시작이에요.');
    setText('reading-after',scriptLines[scriptIndex+1]||'대본의 마지막이에요.');
  }
  $('reading-prev').disabled=busy||pending||scriptIndex===0;
  $('reading-next').disabled=busy||pending||scriptIndex>=scriptLines.length-1;
  refreshPreparation();
  $('change-mode').disabled=busy;
  pager?.refresh();
  setText('flow-navigation-note',busy?'작업 중에는 화면을 넘기지 않아요. 마치거나 취소한 뒤 이동해 주세요.':!guide.analysis?'이 문장의 가이드를 준비하면 녹음 화면으로 갈 수 있어요.':'좌우로 넘기거나 이전·다음 버튼을 눌러 주세요.');
}
function paintPractice(trace=[],progress=null,options={}){
  if(state==='recording'&&session&&!options.live){paintLive(session);return;}
  const live=options.live===true,finished=!live&&result!==null;
  if(finished&&!trace.length)trace=result.trace;
  $('practice-graph-card').dataset.phase=live?'recording':finished?'result':'guide';
  setText('practice-view-label',live?'실시간 · 시간 기준':finished?'녹음 후 · 속도 맞춤':'가이드 미리보기');
  setText('practice-chart-help',live?'파란 점선은 가이드, 굵은 짙은 회색 선·점은 지금 측정한 내 목소리예요. 녹음 중에는 실제 경과 시간으로 보여줘요.':!guide.analysis?'대본에 맞는 AI 가이드를 만들거나 같은 문장의 참고 음성을 넣어 주세요.':finished?'결과창과 같은 비교예요. 파란 점선은 가이드, 짙은 회색 선은 내 목소리예요.':practiceTab==='pitch'?'위쪽은 각 목소리의 중간값보다 높은 음, 아래쪽은 낮은 음이에요. 목소리 크기와는 달라요.':'위쪽은 각 녹음의 중간값보다 큰 소리, 아래쪽은 작은 소리예요. 한 녹음 안의 강약을 볼 수 있어요.');
  if(!live){$('live-status').dataset.voice='idle';setText('live-status',finished?'녹음이 끝났어요. 내 목소리의 움직임을 함께 살펴봐요.':'녹음을 시작하면 짙은 회색 선으로 내 목소리가 나타나요.');}
  drawGraph($('practice-chart'),{reference:guide.analysis,trace,field:field(practiceTab),progress,regions:result?.summary.segments||previewRegions,timeAxis:Boolean(wholeGuide),...options});
  drawGraph($('guide-chart'),{reference:guide.analysis,regions:previewRegions,progress:live?null:progress});
}
function paintLive(s){
  const elapsed=Math.max(0,(performance.now()-s.started)/1000-(s.firstVoice??0));
  const view=s.view.update(s.frames,s.firstVoice===null?0:elapsed);
  $('live-status').dataset.voice=view.hasCurrentVoice?'active':'waiting';
  const message=s.firstVoice===null?'목소리를 기다리고 있어요. 문구를 읽어 보세요.':view.hasCurrentVoice?'내 목소리를 짙은 회색 선과 점으로 표시하고 있어요.':'지금은 높낮이를 확인하기 어려워요. 측정이 되면 짙은 회색 점이 다시 나타나요.';
  if($('live-status').textContent!==message)setText('live-status',message);
  paintPractice(view.trace,s.firstVoice===null?0:elapsed,{live:true,domainSeconds:view.domainSeconds,scaleBound:practiceTab==='volume'?view.levelBound:view.pitchBound});
}
function clearResult(){
  result=null;selectedIndex=0;resultTab='pitch';
  $('practice-coaching').hidden=true;$('reference-segment-play').hidden=true;
  setText('result-status',guide.analysis?'녹음을 마치면 내 목소리를 함께 살펴보고, 연습 팁을 알려드릴게요.':'먼저 같은 문장의 가이드를 준비해 주세요.');
  setText('segment-play','선택한 구간 듣기');
  setText('result-badge','녹음 대기');$('result-badge').classList.remove('demo');
  setText('result-detail','각 녹음의 중간 높이·크기를 기준으로 변화를 보여줘요.');
  $('measurement-values').replaceChildren();$('measurement-details').open=false;
  $('feedback-list').classList.remove('has-result');
  $('feedback-list').innerHTML='<div class="empty-state"><span aria-hidden="true">⌁</span><strong>내 목소리의 흐름을 만나 보세요</strong><p>녹음하거나 데모를 눌러 결과를 확인할 수 있어요.</p></div>';
  if(!guide.analysis)$('feedback-list').innerHTML='<div class="empty-state"><span aria-hidden="true">⌁</span><strong>같은 문장의 가이드를 준비해 주세요</strong><p>가이드와 비교해 다음 연습 방법을 안내해요.</p></div>';
  renderResult();
}
function selectGuide(){
  scriptTracking.stop();
  generation++;stopPreview();clearClip();wholeGuide=null;
  $('region-practice').hidden=true;
  guide=practiceMode==='guide'?(GUIDES.find(g=>g.id===$('guide-select').value)||GUIDES[0]):{
    id:`script-${scriptIndex}`,text:scriptLines[scriptIndex]||'연습할 대본을 입력해 주세요.',source:scriptReferences.get(scriptIndex)?.generated?'대본 AI 가이드':scriptReferences.has(scriptIndex)?'내 참고 음성':'대본 읽기 연습',
    analysis:scriptReferences.get(scriptIndex)?.analysis||null,audioUrl:scriptReferences.get(scriptIndex)?.audioUrl||null,
  };
  document.querySelector('.practice').classList.toggle('no-reference',!guide.analysis);
  setText('phrase-text',guide.text);setText('guide-source',guide.source);setText('timer','00:00');
  setText('recording-phrase-text',guide.text);
  renderGuideRegions();
  setText('practice-status',guide.analysis?'파란 선은 선택한 예시의 흐름이에요. 녹음을 시작하고 같은 문구를 말해 보세요.':'먼저 이 문장의 AI 가이드를 만들거나 참고 음성을 넣어 주세요.');
  $('user-file').value='';state='idle';clearResult();paintPractice();refresh();pager?.goTo(0);
}
function paintStoredRecording(){paintPractice([]);}
function retryFailure(message){
  const notice=result?' 이전 녹음과 결과는 그대로 두었어요.':'';
  setText('practice-status',message+notice);paintStoredRecording();renderResult();refresh();
}
function commitRecording(blob,user,nextResult,{demo=false}={}){
  const url=URL.createObjectURL(blob);
  clearClip();clearResult();clip={blob,url,demo,analysis:user};result=nextResult;
}
function repeatSelectedRegion(){
  if(isBusy()||!result)return;
  const segment=result.summary.segments[selectedIndex];
  stopPlayback();stopPreview();
  pager?.goTo(1);
  setText('practice-status',`‘${guide.text}’ 전체를 다시 읽어 보세요. ${segment.label}(${rangeLabel(segment)})의 움직임을 조금 더 살펴보면 좋아요. 새 녹음이 준비될 때까지 이전 결과는 보관해요.`);
  $('record').scrollIntoView({behavior:'smooth',block:'center'});$('record').focus({preventScroll:true});
}
function leaveRegion(){if(isBusy()||!wholeGuide)return;selectGuide();$('region-practice').hidden=true;}
function showCoaching(message){
  $('practice-coaching').hidden=false;
  $('practice-coaching').dataset.available=String(message.available);
  $('practice-coaching').dataset.tone=message.tone||'neutral';
  setText('coaching-title',message.title);setText('coaching-observation',message.observation);setText('coaching-action',message.action);
  setText('coaching-note',message.detail||message.note||'');
}
function renderResult(){
  const durationView=resultTab==='duration';
  $('result-chart-wrap').hidden=durationView;$('duration-panel').hidden=!durationView;
  $('voice-coverage').hidden=!result;$('feedback-summary').hidden=!result||durationView;
  $('graph-details').hidden=durationView;$('feedback-help').hidden=!result||durationView;
  $('feedback-list').hidden=durationView;$('segment-play').hidden=durationView;
  $('graph-details').classList.remove('solo');
  $('practice-coaching').hidden=!result||durationView;
  $('reference-segment-play').hidden=!result||durationView;
  $('result-phrase').hidden=!result;
  $('region-boundary-note').hidden=!result||durationView;
  $('playback-range-info').hidden=!result||durationView;
  if(!result){
    setText('graph-title',resultTab==='volume'?'강약 비교':'높낮이 비교');setText('graph-selected-label',previewRegions.map(region=>region.label).join(' · ')||'가이드 준비 전');
    setText('result-graph-help',guide.analysis?'녹음하면 예시와 내 목소리를 함께 볼 수 있어요.':'대본에 맞는 가이드를 만들면 파란 선이 나타나요.');
    for(const id of ['reference-duration','user-duration'])setText(id,'—');
    for(const id of ['reference-duration-bar','user-duration-bar'])$(id).style.width='0%';
    setText('duration-delta','녹음을 마치면 말한 길이가 나타나요.');
    drawGraph($('result-chart'),{reference:guide.analysis,empty:true,regions:previewRegions,timeAxis:Boolean(wholeGuide)});refresh();return;
  }
  setText('result-phrase-text',guide.text);
  const total=result.user.recordingDuration,used=result.user.voicedDuration;
  document.querySelector('.coverage-label').textContent='목소리가 확인된 구간만 비교했어요';
  setText('coverage-text',`전체 ${total.toFixed(1)}초 중 ${used.toFixed(1)}초 비교 · ${(total-used).toFixed(1)}초 제외`);
  $('coverage-fill').style.width=`${Math.min(100,used/Math.max(total,.01)*100)}%`;
  setText('graph-title',resultTab==='volume'?'강약 비교':'높낮이 비교');
  setText('graph-selected-label',`${result.summary.segments[selectedIndex].label} 선택됨`);
  setText('result-graph-help','파란 점선은 예시, 짙은 회색 실선은 내 목소리예요. 각 목소리의 중간값을 기준으로 두 흐름을 겹쳐 보여줘요.');
  if(durationView){
    const {reference:r,user:u}=result.summary.duration,max=Math.max(r,u,.1);
    setText('reference-duration',`${r.toFixed(2)}초`);setText('user-duration',`${u.toFixed(2)}초`);
    $('reference-duration-bar').style.width=`${r/max*100}%`;$('user-duration-bar').style.width=`${u/max*100}%`;
    const delta=u-r;setText('duration-delta',Math.abs(delta)<.05?'확인된 목소리의 시간 차이가 0.05초 미만이에요.':`확인된 목소리가 예시보다 ${Math.abs(delta).toFixed(2)}초 ${delta>0?'길어요':'짧아요'}. 이 차이만으로 빠르거나 느리다고 판단하지 않아요.`);
  }else drawGraph($('result-chart'),{reference:guide.analysis,trace:result.trace,field:field(resultTab),selected:result.summary.segments[selectedIndex],regions:result.summary.segments,timeAxis:Boolean(wholeGuide)});
  const feedback=result.summary.segments.map(s=>segmentObservation(s,resultTab));
  const practiceMessages=result.summary.segments.map(s=>describeSegmentPractice(guide.analysis,result.user,result.comparison,s,resultTab));
  if(!durationView){
    const segment=result.summary.segments[selectedIndex],message=feedback[selectedIndex];
    $('feedback-summary').dataset.kind=message.kind;
    setText('summary-label','선택한 구간의 관찰값');
    setText('summary-title',`${segment.label} · ${message.badge}`);
    setText('summary-observation',message.observation);
    setText('summary-detail',message.detail);
    showCoaching(practiceMessages[selectedIndex]);
  }
  const box=$('feedback-list');box.replaceChildren();box.classList.add('has-result');
  box.style.gridTemplateColumns=`repeat(${result.summary.segments.length},minmax(0,1fr))`;
  result.summary.segments.forEach((segment,i)=>{
    const message=practiceMessages[i];
    const button=document.createElement('button');button.type='button';button.className=`feedback-card ${message.available?'observed':'uncertain'}${i===selectedIndex?' selected':''}`;button.setAttribute('aria-pressed',String(i===selectedIndex));
    const tag=document.createElement('span');tag.className='region';tag.textContent=segment.label;
    const symbol=document.createElement('span');symbol.className='feedback-symbol';symbol.textContent=message.icon;symbol.setAttribute('aria-hidden','true');
    const title=document.createElement('strong');title.textContent=message.cardLabel;
    const time=document.createElement('small');time.textContent=rangeLabel(segment);
    button.setAttribute('aria-label',`${segment.label} 가이드 ${rangeLabel(segment)}: ${message.cardLabel}. ${message.observation}`);
    button.append(tag,time,symbol,title);button.addEventListener('click',()=>{selectedIndex=i;stopPlayback();renderResult();});box.append(button);
  });
  const selected=result.summary.segments[selectedIndex];
  const userRange=userPlaybackRange(selected,result.user);
  const referenceRange=playbackRange(guide.analysis,selected);
  setText('segment-play',!userRange?'해당 구간의 녹음 위치를 찾지 못했어요':userRange.whole?'▷ 내 녹음 전체 듣기':`▷ ${selected.label} · 앞뒤 함께 듣기`);
  setText('reference-segment-play',referenceRange.whole?'▷ 가이드 전체 듣기':`▷ 가이드 ${selected.label} · 앞뒤 함께 듣기`);
  setText('region-boundary-note',`${result.summary.segmentationNote||'가이드의 시간 길이를 기준으로 나눈 구간이에요.'} 특정 글자나 단어를 인식한 위치는 아니에요.`);
  setText('playback-range-info',`선택 범위 · 가이드 ${seconds(referenceRange.coreStart)}–${seconds(referenceRange.coreEnd)}${userRange?`, 내 녹음 ${seconds(userRange.coreStart)}–${seconds(userRange.coreEnd)}`:' · 내 녹음에서는 대응 위치를 확인하기 어려워요'}. ${userRange?.whole?'짧은 말은 끊기지 않도록 전체를 재생해요.':'듣기에는 앞뒤 약 0.25초를 함께 넣어요. 단어의 경계를 찾아 자른 것은 아니에요.'}`);
  const values=$('measurement-values');values.replaceChildren();
  for(const segment of result.summary.segments){
    const line=document.createElement('p');
    const measurement=(value,unit)=>Number.isFinite(value)?`${value.toFixed(1)}${unit}`:'비교 보류';
    line.textContent=`${segment.label} 평균 차이 · 높낮이 ${measurement(segment.pitchError,'반음')} / 강약 ${measurement(segment.levelError,'dB')}`;values.append(line);
  }
  const notes=[wholeGuide?'선택한 시간 구간을 하나의 짧은 가이드로 비교했어요. 음절을 인식한 결과가 아니에요.':'앞·중간·끝은 시간 구간이며, 음절을 인식한 결과가 아니에요.'];
  notes.push('차이는 대응하는 측정값 사이 거리의 평균이에요. 오르내리는 방향이나 말하기의 좋고 나쁨을 뜻하지 않아요.');
  notes.push('전체 음높이와 크기를 맞춘 상대 비교예요. 제외한 시간에는 무성 자음과 확인이 어려운 소리도 포함돼요.');
  if(!result.summary.pitchReliable)notes.push('높낮이 추정이 부족해 해당 측정값을 표시하지 않았어요.');
  if(result.summary.duration.user/result.summary.duration.reference>2||result.summary.duration.user/result.summary.duration.reference<.5)notes.push('두 발화의 길이 차이가 커서 대응 위치가 부정확할 수 있어요.');
  notes.push(...result.comparison.warnings);
  if(clip?.demo)notes.push('데모는 높낮이·크기를 일부 바꾼 합성 신호예요. 실제 사람의 말이 아니에요.');
  setText('result-detail',notes.join(' '));refresh();
}
async function decode(blob){
  if(blob.size>25*1024*1024)throw new Error('25MB 이하의 음성 파일을 사용해 주세요.');
  const AC=window.AudioContext||window.webkitAudioContext;
  if(!AC)throw new Error('이 브라우저에서는 음성 분석을 지원하지 않아요.');
  const context=new AC();
  try{
    const buffer=await context.decodeAudioData(await blob.arrayBuffer());
    if(buffer.duration>20.5)throw new Error('20초 이하의 음성 파일을 사용해 주세요.');
    if(buffer.duration<.15)throw new Error('소리가 너무 짧아요. 다시 녹음해 주세요.');
    const samples=new Float32Array(buffer.length);
    for(let c=0;c<buffer.numberOfChannels;c++){const channel=buffer.getChannelData(c);for(let i=0;i<samples.length;i++)samples[i]+=channel[i]/buffer.numberOfChannels;}
    return {samples,sampleRate:buffer.sampleRate};
  }finally{await context.close();}
}
async function processClip(blob,{demo=false,decoded=null}={}){
  if(!guide.analysis){setText('practice-status','먼저 같은 대본의 가이드를 준비해 주세요.');return;}
  const ticket=++generation;let accepted=false;state='processing';stopPreview();stopPlayback();refresh();
  setText('result-status','음성에서 흐름을 찾고 있어요.');
  await new Promise(resolve=>setTimeout(resolve,35));
  try{
    if(ticket!==generation)return;
    const audio=decoded||await decode(blob);if(ticket!==generation)return;
    const user=trimAnalysis(analyzeAudio(audio.samples,audio.sampleRate));
    if(user.duration<.15||user.voicedFrames<8||!user.pitchMedian)throw new Error('앱이 목소리를 충분히 잡지 못했어요. 마이크 위치를 확인하고, 준비되면 편하게 다시 읽어 주세요.');
    const comparison=compareAnalyses(guide.analysis,user);
    if(!comparison.path.length)throw new Error(comparison.warnings[0]||'두 소리를 비교하기 어려워요. 다시 녹음해 주세요.');
    const nextResult={user,comparison,summary:buildPracticeSummary(guide.analysis,user,comparison,{whole:Boolean(wholeGuide)}),trace:alignedTrace(guide.analysis,user,comparison.path)};
    commitRecording(blob,user,nextResult,{demo});
    accepted=true;
    if(practiceMode==='script'&&!demo){practicedSentences.add(scriptIndex);updateScriptStatus();}
    selectedIndex=0;
    setText('result-badge',demo?'데모 신호':'내 녹음');$('result-badge').classList.toggle('demo',demo);
    setText('result-status',`${guide.text} · ${demo?'합성 신호로 비교 동작을 보여드려요.':'궁금한 부분을 골라 보세요. 그 부분부터 함께 살펴봐요.'}`);
    setText('practice-status',demo?'데모가 준비됐어요. 실제로 말해 보려면 녹음 시작을 눌러 주세요.':'분석을 마쳤어요. 결과에서 살펴보고 싶은 구간을 골라 보세요.');
    paintPractice();
  }catch(error){
    if(ticket!==generation)return;
    const message=error.message||'분석을 마치지 못했어요. 다시 시도해 주세요.';
    setText('result-status',message+(result?' 이전 녹음과 결과는 그대로 두었어요.':''));
    if(!result)setText('result-badge','다시 확인해요');
    setText('practice-status',result?'이번 입력은 반영하지 않았어요. 이전 녹음을 다시 듣거나 새로 녹음할 수 있어요.':'입력을 확인한 뒤 다시 녹음하거나 다른 음성 파일을 선택해 주세요.');
    paintStoredRecording();
  }finally{if(ticket===generation){state='idle';renderResult();refresh();if(accepted)pager?.goTo(2);}}
}
function releaseSession(s){
  if(s.released)return;s.released=true;
  scriptTracking.stop();
  clearInterval(s.liveTimer);clearTimeout(s.timeout);s.stream?.getTracks().forEach(t=>t.stop());
  try{s.source?.disconnect();s.analyser?.disconnect();}catch{}
  if(s.context&&s.context.state!=='closed')s.context.close().catch(()=>{});
}
async function record(){
  if(state==='recording'){if(session?.recorder.state!=='inactive')session.recorder.stop();return;}
  if(isBusy())return;
  if(draftPending()){setText('practice-status','수정한 대본으로 연습 준비를 먼저 눌러 주세요.');return;}
  if(!guide.analysis){setText('practice-status','먼저 같은 대본의 가이드를 준비해 주세요.');return;}
  if(!navigator.mediaDevices?.getUserMedia||!window.MediaRecorder){setText('practice-status','이 브라우저에서 마이크를 사용할 수 없어요. Safari·Chrome의 보안 연결 또는 로컬 주소에서 열어 주세요. 파일 비교와 데모도 사용할 수 있어요.');return;}
  if(practiceMode==='script'&&$('asr-enabled').checked&&!scriptTracking.ready){setText('practice-status','음성 위치 표시를 먼저 준비하거나 체크를 꺼 주세요.');return;}
  const ticket=++generation;state='requesting';stopPlayback();stopPreview();setText('timer','00:00');refresh();
  setText('practice-status','마이크 접근을 허용하면 녹음이 시작돼요.');
  let stream,context,s;
  try{
    stream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:false,noiseSuppression:false,autoGainControl:false},video:false});
    if(ticket!==generation){stream.getTracks().forEach(t=>t.stop());return;}
    s={stream};session=s;
    const AC=window.AudioContext||window.webkitAudioContext;context=new AC();s.context=context;await context.resume();
    if(ticket!==generation||document.hidden){if(session===s)cancelRecording();else releaseSession(s);return;}
    const source=context.createMediaStreamSource(stream);s.source=source;
    const analyser=context.createAnalyser();s.analyser=analyser;analyser.fftSize=4096;source.connect(analyser);
    if(practiceMode==='script'&&$('asr-enabled').checked){
      try{await scriptTracking.attach(stream,appliedScript,scriptLines,scriptIndex);}
      catch{scriptTracking.stop();setText('asr-status','이 기기에서 음성 위치 표시를 시작하지 못했어요. 녹음은 계속해요.');}
      if(ticket!==generation||document.hidden){releaseSession(s);return;}
    }
    const recorder=new MediaRecorder(stream),chunks=[];Object.assign(s,{recorder,failed:false,cancelled:false,frames:[],firstVoice:null,view:createLiveView(guide.analysis)});
    recorder.addEventListener('dataavailable',e=>{if(e.data.size)chunks.push(e.data);});
    recorder.addEventListener('error',()=>{s.failed=true;if(recorder.state!=='inactive')recorder.stop();else finish();},{once:true});
    let finished=false;
    function finish(){
      if(finished)return;finished=true;releaseSession(s);if(session===s)session=null;
      if(s.cancelled)return;
      if(s.failed){state='idle';retryFailure('녹음에 문제가 생겼어요. 다시 시도해 주세요.');return;}
      const blob=new Blob(chunks,{type:recorder.mimeType||'audio/webm'});
      if(!blob.size){state='idle';retryFailure('녹음된 소리를 읽지 못했어요. 다시 시도해 주세요.');return;}
      processClip(blob);
    }
    recorder.addEventListener('stop',finish,{once:true});
    recorder.start();state='recording';s.started=performance.now();refresh();paintLive(s);
    setText('practice-status','짙은 회색 선과 점을 보며 같은 문구를 읽어 보세요. 녹음을 마치면 말하는 속도를 맞춰 다시 비교해요.');
    const data=new Float32Array(analyser.fftSize);
    s.liveTimer=setInterval(()=>{
      const elapsed=(performance.now()-s.started)/1000;setText('timer',`00:${String(Math.floor(elapsed)).padStart(2,'0')}`);
      analyser.getFloatTimeDomainData(data);
      const frameSamples=data.subarray(Math.max(0,data.length-Math.round(context.sampleRate*.05)));
      const f=analyzeFrame(frameSamples,context.sampleRate);
      if(s.firstVoice===null&&f.active)s.firstVoice=elapsed;
      if(s.firstVoice!==null)s.frames.push({...f,time:elapsed-s.firstVoice});
      paintLive(s);
    },40);
    s.timeout=setTimeout(()=>{if(recorder.state!=='inactive')recorder.stop();},20000);
    stream.getAudioTracks()[0]?.addEventListener('ended',()=>{if(recorder.state!=='inactive')recorder.stop();},{once:true});
  }catch(error){if(s)releaseSession(s);else stream?.getTracks().forEach(t=>t.stop());if(ticket!==generation)return;if(session===s)session=null;state='idle';retryFailure(error.name==='NotAllowedError'?'마이크 접근이 허용되지 않았어요. 브라우저에서 권한을 바꾸거나 음성 파일로 시험해 보세요.':'마이크를 시작하지 못했어요. 연결을 확인하거나 음성 파일로 시험해 보세요.');}
}
async function playUrl(url,start=0,end=null,label=''){
  stopPlayback();const audio=new Audio(url);playback=audio;
  try{
    if(start>0)await new Promise((resolve,reject)=>{audio.addEventListener('loadedmetadata',resolve,{once:true});audio.addEventListener('error',reject,{once:true});audio.load();});
    if(playback!==audio)return;
    audio.currentTime=start;await audio.play();
    if(playback!==audio){audio.pause();return;}
    if(label){$('listening-status').hidden=false;setText('listening-status',`${label} · ${seconds(start)}${end===null?'':`–${seconds(end)}`} 재생 중`);}
    audio.addEventListener('ended',()=>{if(playback===audio)stopPlayback();},{once:true});
    if(end!==null)playbackTimer=setTimeout(()=>{if(playback===audio)stopPlayback();},Math.max(.1,end-start)*1000);
  }catch{setText('practice-status','소리를 재생하지 못했어요. 브라우저의 소리 설정을 확인해 주세요.');}
}
function preview(){
  if(!guide.analysis)return;
  if(previewTimer){stopPreview();paintPractice();return;}
  stopPlayback();const started=performance.now(),duration=guide.analysis.duration*1.8;
  $('guide-preview').textContent='■ 움직임 멈추기';
  setText('practice-status','파란 선을 따라 예시의 흐름을 살펴보세요. 이 움직임은 보기 편하게 천천히 재생돼요.');
  previewTimer=setInterval(()=>{const elapsed=(performance.now()-started)/1000;paintPractice([],Math.min(guide.analysis.duration,elapsed/1.8));if(elapsed>=duration){stopPreview();paintPractice();}},40);
}
function updateScriptStatus(){
  if(!scriptLines.length)return;
  const unit=scriptUnits[scriptIndex];
  const position=`${scriptLines.length}개 중 ${scriptIndex+1}번째${unit.partCount>1?` · 원문 ${unit.sentenceIndex+1}번째 문장의 ${unit.partIndex+1}/${unit.partCount} 조각`:''}`;
  setText('script-status',`${position} · 가이드 ${scriptReferences.size}/${scriptLines.length}개 준비 · ${practicedSentences.size}개 녹음함`);
  setText('sentence-position',`지금 읽을 문장 · ${position}`);
  setText('sentence-current-text',scriptLines[scriptIndex]);
  const list=$('sentence-list');list.replaceChildren();
  scriptUnits.forEach((item,i)=>{
    const button=document.createElement('button');button.type='button';button.setAttribute('aria-pressed',String(i===scriptIndex));
    const number=document.createElement('span');number.textContent=String(i+1).padStart(2,'0');
    const label=document.createElement('strong');label.textContent=item.text;
    const status=document.createElement('small');
    const preparation=guideBatch?.currentId===i?'만드는 중':scriptReferences.has(i)?'가이드 준비됨':guideFailures.has(i)?'다시 준비':'준비 전';
    status.textContent=`${i===scriptIndex?'선택 · ':''}${practicedSentences.has(i)?'녹음함':preparation}`;
    if(guideFailures.has(i))button.title=guideFailures.get(i);
    button.append(number,label,status);button.addEventListener('click',()=>chooseSentence(i));list.append(button);
  });
  const ref=scriptReferences.get(scriptIndex);
  setText('reference-status',ref?`${ref.generated?'생성한 가이드':'연결한 파일'}: ${ref.name} · ${ref.analysis.voicedDuration.toFixed(1)}초의 목소리 확인. 대본과 같은 문장의 음성인지 확인해 주세요.`:'AI 가이드를 만들거나 같은 문장을 읽은 참고 파일을 연결해 주세요.');
  if(state!=='generating')setText('generation-status',guideNotice||(scriptReferences.size===scriptLines.length?'전체 가이드가 준비됐어요. 문장을 바꿔도 바로 연습할 수 있어요.':`전체 가이드 만들기를 한 번 누르면 ${scriptLines.length}개 문장을 차례로 준비해요.`));
  $('remove-reference').hidden=!ref;
}
function refreshPreparation(){
  const script=practiceMode==='script';
  $('prepare-tabs').hidden=!script;
  $('script-editor').hidden=!script||prepareView==='preview';
  $('script-edit-panel').hidden=prepareView!=='edit';
  $('script-session').hidden=prepareView!=='build'||!scriptLines.length;
  $('guide-preview-panel').hidden=script&&prepareView!=='preview';
  for(const view of ['edit','build','preview']){
    const button=$('prepare-'+view);
    button.setAttribute('aria-pressed',String(view===prepareView));
    button.disabled=isBusy()||(view!=='edit'&&(!scriptLines.length||draftPending()));
  }
}
function showPreparation(view){
  if(isBusy()||(view!=='edit'&&(!scriptLines.length||draftPending())))return;
  prepareView=view;refreshPreparation();paintPractice();
  $('flow-prepare').scrollTop=0;
}
function switchMode(mode){
  if(isBusy())return;
  $('mode-choice').hidden=true;$('practice-workflow').hidden=false;
  setText('selected-mode-label',mode==='script'?'내 대본으로 연습':'준비된 예시');
  if(mode===practiceMode){
    refresh();
    // The workflow was hidden; clientWidth now reflects the displayed layout.
    // Redraw without replacing the selected guide, recording, or comparison.
    paintPractice();renderResult();
    $('flow-deck').scrollIntoView({block:'start'});
    document.querySelectorAll('[data-flow-step]')[pager?.index||0]?.focus({preventScroll:true});
    return;
  }
  prepareView=scriptLines.length?'build':'edit';
  practiceMode=mode;$('script-editor').hidden=mode!=='script';$('guide-select').hidden=mode==='script';
  selectGuide();updateScriptStatus();
  $(mode==='script'?'prepare-'+prepareView:'guide-heading').focus({preventScroll:true});
}
function chooseSentence(index){
  if(isBusy()||draftPending()||index<0||index>=scriptLines.length)return;
  scriptIndex=index;$('script-sentence-select').value=String(index);selectGuide();updateScriptStatus();
  $('sentence-current-card').scrollIntoView({block:'nearest'});
}
function applyScript(){
  if(isBusy())return;
  try{
    const units=parsePracticeScript($('script-input').value),parsed=units.map(unit=>unit.text);
    for(const ref of scriptReferences.values())URL.revokeObjectURL(ref.audioUrl);
    scriptReferences.clear();practicedSentences.clear();guideFailures.clear();guideNotice='';scriptLines=parsed;scriptUnits=units;scriptIndex=0;appliedScript=$('script-input').value;
    const select=$('script-sentence-select');select.replaceChildren();
    parsed.forEach((text,i)=>{const option=document.createElement('option');option.value=String(i);option.textContent=`${i+1}. ${text.length>40?text.slice(0,40)+'…':text}`;select.append(option);});
    prepareView='build';$('script-session').hidden=false;chooseSentence(0);$('guide-batch-panel').scrollIntoView({block:'nearest'});
  }catch(error){setText('script-status',error.message);}
}
function syncScriptReference(){
  if(practiceMode!=='script'||!scriptLines.length)return;
  // After a partial preparation, start with a ready sentence if the currently
  // selected one failed or was not reached. Keep accepted comparisons whenever
  // their actual reference was not replaced.
  if(!scriptReferences.has(scriptIndex)&&scriptReferences.size){
    scriptIndex=scriptLines.findIndex((_,i)=>scriptReferences.has(i));
    $('script-sentence-select').value=String(scriptIndex);
  }
  const ref=scriptReferences.get(scriptIndex);
  if(guide.id!==`script-${scriptIndex}`||guide.analysis!==(ref?.analysis||null))selectGuide();
  updateScriptStatus();refresh();
}
function paintBatchProgress(run,snapshot){
  if(guideBatch!==run||run.controller.signal.aborted||run.ticket!==generation)return;
  run.currentId=snapshot.phase==='generating'?snapshot.currentItem?.id:null;
  for(const failure of snapshot.failures)guideFailures.set(failure.id,failure.message);
  const prefix=run.replaceSelected?'선택한 문장 다시 만들기':`${scriptReferences.size}/${scriptLines.length}개 준비`;
  const current=snapshot.currentIndex===null?'':` · ${snapshot.currentItem.id+1}번째 문장`;
  const progress=typeof snapshot.progress==='string'?snapshot.progress:snapshot.progress?.message;
  setText('generation-status',`${prefix}${current}${progress?` · ${progress}`:snapshot.phase==='generating'?' 만드는 중…':''}`);
  const key=`${snapshot.phase}:${run.currentId}:${scriptReferences.size}:${snapshot.failed}`;
  if(run.paintKey!==key){run.paintKey=key;updateScriptStatus();refresh();}
}
async function makeScriptGuide({replaceSelected=false}={}){
  if(!isBusy())scriptTracking.stop();
  if(isBusy()||draftPending()||practiceMode!=='script'||!scriptLines.length)return;
  if(!replaceSelected&&scriptReferences.size===scriptLines.length)return;
  const run={ticket:++generation,controller:new AbortController(),replaceSelected,currentId:null};
  guideBatch=run;guideNotice='';
  const items=replaceSelected?[{id:scriptIndex,text:scriptLines[scriptIndex]}]:scriptLines.map((text,id)=>({id,text}));
  state='generating';stopPlayback();stopPreview();refresh();setText('generation-status','전체 가이드를 준비하고 있어요.');
  try{
    const summary=await runGuideBatch({items,signal:run.controller.signal,
      hasGuide:item=>!replaceSelected&&scriptReferences.has(item.id),
      generate:async(item,{onProgress})=>{
        const audio=await generateGuide(item.text,{onProgress});
        if(run.controller.signal.aborted||run.ticket!==generation)throw new DOMException('취소했어요.','AbortError');
        if(audio.samples.length/audio.sampleRate>20)throw new Error('음성이 20초보다 길어요. 이 문장을 더 짧게 나눠 주세요.');
        const analysis=trimAnalysis(analyzeAudio(audio.samples,audio.sampleRate));
        if(analysis.voicedFrames<15||!analysis.pitchMedian)throw new Error('높낮이를 충분히 찾지 못했어요. 이 문장을 조금 다듬어 다시 만들어 주세요.');
        return {analysis,blob:new Blob([wavBytes(audio.samples,audio.sampleRate)],{type:'audio/wav'})};
      },
      commit:(item,value)=>{
        if(guideBatch!==run||run.controller.signal.aborted||run.ticket!==generation)return;
        const previous=scriptReferences.get(item.id);
        scriptReferences.set(item.id,{analysis:value.analysis,audioUrl:URL.createObjectURL(value.blob),name:'Supertonic 3 · 한국어 예시',generated:true});
        guideFailures.delete(item.id);
        if(previous)URL.revokeObjectURL(previous.audioUrl);
      },
      onUpdate:snapshot=>paintBatchProgress(run,snapshot),
    });
    if(guideBatch!==run||run.ticket!==generation)return;
    if(summary.cancelled){
      guideNotice=`가이드 준비를 멈췄어요. 준비된 ${scriptReferences.size}개는 그대로 보관했어요. 나머지는 이어서 만들 수 있어요.`;
    }else if(replaceSelected&&summary.failures.length){
      guideNotice=`새 가이드를 만들지 못했어요. 이전 가이드는 그대로 사용할 수 있어요. ${summary.failures[0].message}`;
    }else if(summary.failures.length){
      const failed=summary.failures.map(failure=>`${failure.id+1}번`).join(', ');
      guideNotice=`${scriptReferences.size}/${scriptLines.length}개 가이드가 준비됐어요. ${failed} 문장은 다시 준비가 필요해요. ‘남은 가이드 만들기’로 이어서 준비할 수 있어요. ${summary.failures[0].message}`;
    }else if(!replaceSelected&&scriptReferences.size!==scriptLines.length){
      guideNotice=`${scriptReferences.size}/${scriptLines.length}개 가이드를 준비했어요. 남은 가이드는 이어서 만들 수 있어요.`;
    }else guideNotice=replaceSelected?'선택한 문장의 가이드를 새로 준비했어요.':`전체 ${scriptLines.length}개 가이드가 준비됐어요. 이제 문장만 골라 연습해 보세요.`;
  }catch(error){if(guideBatch===run&&run.ticket===generation)guideNotice=`가이드 준비를 마치지 못했어요. ${scriptReferences.size}개는 그대로 보관했어요. ${error.message||''}`;}
  finally{if(guideBatch===run&&run.ticket===generation){guideBatch=null;state='idle';syncScriptReference();}}
}
function cancelScriptGuide(){
  if(state!=='generating')return;
  const run=guideBatch;guideBatch=null;generation++;run?.controller.abort();cancelGuide();state='idle';
  guideNotice=`생성을 멈췄어요. 준비된 ${scriptReferences.size}개 가이드는 그대로 두었어요. 나머지는 나중에 이어서 만들 수 있어요.`;
  syncScriptReference();
}
async function loadReference(file){
  if(isBusy()||draftPending()||practiceMode!=='script'||!scriptLines.length)return;
  const ticket=++generation,index=scriptIndex;state='processing';stopPreview();stopPlayback();refresh();
  setText('reference-status','참고 음성에서 목소리를 확인하고 있어요.');
  try{
    const audio=await decode(file);if(ticket!==generation)return;
    const analysis=trimAnalysis(analyzeAudio(audio.samples,audio.sampleRate));
    if(analysis.voicedFrames<15||!analysis.pitchMedian)throw new Error('참고 음성에서 충분한 목소리를 찾지 못했어요. 같은 문장을 또렷하게 읽은 파일을 넣어 주세요.');
    const previous=scriptReferences.get(index);
    const next={analysis,audioUrl:URL.createObjectURL(file),name:file.name};
    scriptReferences.set(index,next);guideFailures.delete(index);guideNotice='';if(previous)URL.revokeObjectURL(previous.audioUrl);
    state='idle';selectGuide();updateScriptStatus();
  }catch(error){if(ticket===generation)setText('reference-status',`${error.message} 기존 참고 음성이 있다면 그대로 유지돼요.`);}
  finally{if(ticket===generation){state='idle';refresh();}}
}
function readScript(){
  if(isBusy()||practiceMode!=='script'||!scriptLines.length)return;
  stopPlayback();stopPreview();
  const voice=selectLocalKoreanVoice(window.speechSynthesis?.getVoices()||[]);
  if(!voice||!window.SpeechSynthesisUtterance){setText('practice-status','이 기기에서 설치된 한국어 읽기 음성을 찾지 못했어요. 대본을 직접 읽거나 참고 음성 파일을 넣어 연습해 주세요.');return;}
  const utterance=new SpeechSynthesisUtterance(guide.text);utterance.voice=voice;utterance.lang=voice.lang;utterance.rate=.9;ttsUtterance=utterance;
  setText('practice-status','기기의 한국어 음성으로 읽고 있어요. 읽어주기 소리는 비교할 음성 파일로 저장되지 않아요.');
  utterance.onend=()=>{if(ttsUtterance!==utterance)return;ttsUtterance=null;setText('practice-status','이제 같은 문장을 읽어보세요. 녹음 시작을 누르면 돼요.');};
  utterance.onerror=()=>{if(ttsUtterance!==utterance)return;ttsUtterance=null;setText('practice-status','기기 읽어주기를 실행하지 못했어요. 직접 읽거나 참고 음성을 넣어 연습해 주세요.');};
  window.speechSynthesis.speak(utterance);
}
for(const g of GUIDES){const option=document.createElement('option');option.value=g.id;option.textContent=`${g.kind==='word'?'단어':'구절'} · ${g.text}`;$('guide-select').append(option);}
$('guide-select').addEventListener('change',selectGuide);
$('prepare-asr').addEventListener('click',async()=>{
  if(isBusy()||practiceMode!=='script'||!$('asr-enabled').checked)return;
  const ticket=++generation;state='asr-loading';refresh();
  try{await scriptTracking.prepare();}catch{if(ticket===generation)setText('asr-status','모델 준비를 완료하지 못했어요. 연결·메모리를 확인하고 다시 시도해 주세요.');}
  finally{if(ticket===generation){state='idle';refresh();}}
});
$('cancel-asr').addEventListener('click',()=>{
  scriptTracking.stop();$('asr-enabled').checked=false;
  if(state==='asr-loading'){generation++;state='idle';}
  setText('asr-status','음성 위치 표시를 껐어요.');refresh();
});
$('asr-enabled').addEventListener('change',()=>{if(!$('asr-enabled').checked)scriptTracking.stop();refresh();});
$('record').addEventListener('click',record);
$('guide-preview').addEventListener('click',preview);
$('result-chart').addEventListener('click',event=>{if(!result||resultTab==='duration'||wholeGuide)return;const index=graphSegmentAt($('result-chart'),guide.analysis,event.clientX,event.clientY,result.summary.segments);if(index!==null){selectedIndex=index;stopPlayback();renderResult();}});
$('guide-play').addEventListener('click',()=>{if(!guide.audioUrl){readScript();return;}stopPreview();paintPractice();const start=wholeGuide?(guide.analysis.startTime||0):0;playUrl(guide.audioUrl,start,wholeGuide?start+guide.analysis.duration:null);});
$('user-file').addEventListener('change',e=>{const file=e.target.files[0];if(file)processClip(file);e.target.value='';});
$('user-play').addEventListener('click',()=>{if(clip)playUrl(clip.url);});
$('segment-play').addEventListener('click',()=>{if(!clip||!result)return;const segment=result.summary.segments[selectedIndex],range=userPlaybackRange(segment,result.user);if(range)playUrl(clip.url,range.start,range.end,`내 녹음 · ${range.whole?'전체':segment.label}`);});
$('reference-segment-play').addEventListener('click',()=>{if(!result||!guide.audioUrl)return;const segment=result.summary.segments[selectedIndex],range=playbackRange(guide.analysis,segment);playUrl(guide.audioUrl,range.start,range.end,`가이드 · ${range.whole?'전체':segment.label}`);});
$('repeat-region').addEventListener('click',repeatSelectedRegion);
$('next-sentence-result').addEventListener('click',()=>chooseSentence(scriptIndex+1));
$('leave-region').addEventListener('click',leaveRegion);
$('reset').addEventListener('click',selectGuide);
$('retry').addEventListener('click',()=>{stopPlayback();pager?.goTo(1);$('record').scrollIntoView({behavior:'smooth',block:'center'});$('record').focus({preventScroll:true});setText('practice-status','같은 예시로 다시 연습해 보세요. 새 녹음의 분석에 성공하면 결과를 바꿔 드려요.');});
for(const button of document.querySelectorAll('[data-practice-tab]'))button.addEventListener('click',()=>{practiceTab=button.dataset.practiceTab;paintPractice();refresh();});
for(const button of document.querySelectorAll('[data-result-tab]'))button.addEventListener('click',()=>{
  resultTab=button.dataset.resultTab;stopPlayback();renderResult();
});
for(const [id,delta] of [['reading-prev',-1],['reading-next',1]])$(id).addEventListener('click',()=>{chooseSentence(scriptIndex+delta);if(guide.analysis)pager?.goTo(1);else showPreparation('build');});
$('change-mode').addEventListener('click',()=>{if(isBusy())return;stopPlayback();stopPreview();$('practice-workflow').hidden=true;$('mode-choice').hidden=false;$('mode-choice-heading').focus({preventScroll:true});});
for(const view of ['edit','build','preview'])$('prepare-'+view).addEventListener('click',()=>showPreparation(view));
for(const button of document.querySelectorAll('[data-mode]'))button.addEventListener('click',()=>switchMode(button.dataset.mode));
$('generate-guide').addEventListener('click',()=>makeScriptGuide());
$('regenerate-guide').addEventListener('click',()=>makeScriptGuide({replaceSelected:true}));
$('cancel-guide').addEventListener('click',cancelScriptGuide);
$('script-input').addEventListener('input',()=>{setText('script-count',`${Array.from($('script-input').value).length.toLocaleString()} / 2,000자`);refresh();});
$('apply-script').addEventListener('click',applyScript);
$('script-sentence-select').addEventListener('change',()=>chooseSentence(Number($('script-sentence-select').value)));
$('sentence-prev').addEventListener('click',()=>chooseSentence(scriptIndex-1));$('sentence-next').addEventListener('click',()=>chooseSentence(scriptIndex+1));
$('reference-file').addEventListener('change',event=>{const file=event.target.files[0];if(file)loadReference(file);event.target.value='';});
$('remove-reference').addEventListener('click',()=>{const ref=scriptReferences.get(scriptIndex);if(!ref||isBusy()||draftPending())return;URL.revokeObjectURL(ref.audioUrl);scriptReferences.delete(scriptIndex);guideFailures.delete(scriptIndex);guideNotice='';selectGuide();updateScriptStatus();});
window.speechSynthesis?.addEventListener('voiceschanged',refresh);
function cancelRecording(){scriptTracking.stop();const run=guideBatch;guideBatch=null;generation++;run?.controller.abort();cancelGuide();if(session){const s=session;s.cancelled=true;session=null;if(s.recorder&&s.recorder.state!=='inactive')s.recorder.stop();releaseSession(s);}state='idle';stopPreview();stopPlayback();if(run){guideNotice=`가이드 준비를 멈췄어요. 준비된 ${scriptReferences.size}개는 그대로 보관했어요.`;syncScriptReference();}paintStoredRecording();renderResult();refresh();}
// The Flutter host calls this synchronously before removing the same-origin
// frame. A queued postMessage alone can be lost during immediate disposal.
window.voiceMateProsodyCleanup=cancelRecording;
window.addEventListener('message',event=>{if(event.origin===location.origin&&event.source===window.parent&&event.data?.type==='voicemate:prosody:cleanup')cancelRecording();});
window.addEventListener('pagehide',()=>{cancelRecording();clearClip();for(const ref of scriptReferences.values())URL.revokeObjectURL(ref.audioUrl);scriptReferences.clear();});
window.addEventListener('pageshow',event=>{if(event.persisted){selectGuide();updateScriptStatus();}});
window.addEventListener('resize',()=>{paintPractice();renderResult();});
document.addEventListener('visibilitychange',()=>{if(document.hidden)scriptTracking.stop();if(document.hidden&&!isBusy()){stopPreview();stopPlayback();paintStoredRecording();}if(document.hidden&&isBusy()){const generating=state==='generating';cancelRecording();setText(generating?'generation-status':'practice-status',generating?'화면을 벗어나 가이드 생성을 중지했어요. 다시 시도해 주세요.':'화면을 벗어나 녹음을 중지했어요. 다시 시작해 주세요.');}});
if(new URLSearchParams(location.search).get('embedded')==='1'){
  document.body.classList.add('embedded');
}
if(document.body)document.body.dataset.currentFlow='0';
pager=createFlowPager({
  pages:[$('flow-prepare'),$('flow-record'),$('flow-results')],
  stepButtons:Array.from(document.querySelectorAll('[data-flow-step]')),
  previousButton:$('flow-previous'),nextButton:$('flow-next'),positionLabel:$('flow-position'),gestureTarget:$('flow-deck'),
  canEnter:index=>index===0||(index===1&&Boolean(guide.analysis)&&!draftPending())||(index===2&&Boolean(result)),
  canMove:()=>!isBusy(),
  onChanged:index=>{if(document.body)document.body.dataset.currentFlow=String(index);if(document.activeElement?.closest('.flow-page'))document.activeElement.blur();stopPlayback();stopPreview();paintPractice();renderResult();$('flow-deck').scrollIntoView({block:'start'});},
});
selectGuide();
