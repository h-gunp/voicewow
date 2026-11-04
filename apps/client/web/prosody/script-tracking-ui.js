import {AsrClient} from './asr-client.js';
import {startAsrPcmBridge} from './asr-pcm-bridge.js';
import {ScriptTracker,sourceRanges} from './script-alignment.js';

export function createScriptTracking({document,cancelTts}){
  const el=id=>document.getElementById(id);
  let client=null,bridge=null,captureAbort=null,ready=false,ticket=0,tracker=null;
  const message=text=>{el('asr-status').textContent=text;};
  function clear(){el('asr-before').textContent='';el('asr-match').textContent='';el('asr-after').textContent='';}
  function stop(){ticket++;ready=false;captureAbort?.abort();captureAbort=null;bridge?.stop();bridge=null;client?.stop();client=null;tracker=null;clear();}
  function render(result){
    clear();
    if(!result.range){message(result.status==='ambiguous'?'같은 문구가 반복돼 위치를 구분하지 못했어요.':'읽은 위치를 확인 중이에요. 대본과 다른 말은 표시하지 않아요.');return;}
    el('asr-before').textContent=result.before;el('asr-match').textContent=result.text;el('asr-after').textContent=result.after;
    message(result.status==='uncertain-tail'?'표시한 부분은 앞서 인식된 문구예요. 그 뒤의 현재 위치는 불확실해요.':'인식된 말과 일치하는 대본 범위예요. 정확한 발음·글자별 시점을 뜻하지 않아요.');
  }
  return {
    get ready(){return ready;},
    stop,
    async prepare(){
      stop();cancelTts();const current=ticket;
      clear();message('기기 안 음성 인식을 준비하고 있어요.');
      client=new AsrClient({onProgress:p=>{if(current===ticket)message(`음성 인식 모델 준비 ${Math.floor(p.loaded/p.total*100)}% · 처음 약 141MB`);},
        onResult:r=>{if(current!==ticket||!tracker)return;render(tracker.update({text:r.text,sequence:r.sequence,final:r.endpoint===true}));if(r.endpoint)tracker.reset();},
        onError:()=>{if(current===ticket){stop();message('음성 위치 표시가 중단됐어요. 녹음은 계속할 수 있어요. 다시 준비해 주세요.');}}
      });
      await client.prepare();if(current!==ticket)throw Error('Cancelled');ready=true;message('준비됐어요. 연습을 시작하면 기기 안에서 대본 위치를 추정해요.');
    },
    async attach(stream,source,chunks,index){
      if(!ready||!client)throw Error('ASR not ready');
      const current=ticket,active=client;
      tracker=new ScriptTracker(source,sourceRanges(source,chunks)[index]);clear();
      captureAbort=new AbortController();
      const created=await startAsrPcmBridge({stream,signal:captureAbort.signal,onChunk:chunk=>active.consume(chunk),onError:()=>{
        if(current===ticket){stop();message('처리가 녹음 속도를 따라가지 못해 위치 표시를 멈췄어요.');}
      }});
      if(current!==ticket){created.stop();throw Error('Cancelled');}
      bridge=created;
    },
  };
}
