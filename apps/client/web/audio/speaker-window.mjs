// PCM remains local to the worklet unless explicitly enabled by the caller.
export function createSpeakerWindow(onWindow) {
  let enabled=false,seq=0,pos=0,partial=null,frames=new Map(),selected=[],lastSeq=null;
  function clear() { partial?.fill(0);partial=null;for(const v of frames.values())v.fill(0);frames.clear();for(const v of selected)v.pcm.fill(0);selected=[];lastSeq=null; }
  return {
    enable(){clear();enabled=true;},
    disable(){enabled=false;clear();},
    reset(){clear();seq=pos=0;},
    push(input){
      for(const sample of input){
        if(enabled&&pos===0)partial=new Float32Array(480);
        if(enabled&&partial)partial[pos]=sample;
        if(++pos===480){if(enabled&&partial)frames.set(seq,partial);partial=null;pos=0;seq++;}
      }
      while(frames.size>110){const key=frames.keys().next().value;frames.get(key).fill(0);frames.delete(key);}
    },
    analysis(frame){
      if(!enabled)return;
      const pcm=frames.get(frame.seq);if(!pcm)return;
      frames.delete(frame.seq);
      if(lastSeq!==null&&frame.seq!==lastSeq+1){for(const item of selected)item.pcm.fill(0);selected=[];}
      lastSeq=frame.seq;selected.push({pcm,speech:frame.speech==='speech',clipped:frame.clipped===true,seq:frame.seq});
      if(selected.length!==100)return;
      const output=new Float32Array(48000);let speechFrames=0,clipped=false;
      for(let i=0;i<100;i++){const item=selected[i];output.set(item.pcm,i*480);item.pcm.fill(0);if(item.speech)speechFrames++;clipped ||= item.clipped;}
      const sampleStart=selected[0].seq*480,sampleEnd=(selected[99].seq+1)*480;selected=[];
      onWindow({pcm:output,sampleStart,sampleEnd,speechFrames,clipped});
    },
  };
}
