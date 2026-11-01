import {createSpeakerSession} from './speaker-session.mjs';
import {speakerStatus} from './speaker-status.mjs';

// Experimental status is separate from the input meter and does not authenticate anyone.
export function createSpeakerFlow({embed,cancel,onStatus,now}) {
  let epoch=0, generation=0, phase='unregistered', samples=[], busy=false;
  function clearSamples(){for(const sample of samples)sample.fill(0);samples=[];}
  const session=createSpeakerSession({cancel,run:async(pcm,profile)=>{
    const vector=await embed(pcm);try{
      if(!(vector instanceof Float32Array)||vector.length!==profile.length||!vector.every(Number.isFinite))throw Error('Invalid embedding');
      let dot=0,aa=0,bb=0;for(let i=0;i<vector.length;i++){dot+=vector[i]*profile[i];aa+=vector[i]**2;bb+=profile[i]**2;}
      if(!aa||!bb)throw Error('Invalid embedding');return dot/Math.sqrt(aa*bb);
    }finally{vector?.fill?.(0);}
  },onResult:(score,m)=>{const status=speakerStatus({score,...m,receivedTime:now(),currentEpoch:epoch});if(status.state==='unavailable')unavailable();else onStatus(status);},onError:unavailable});
  function unavailable(){epoch++;session.resetEpoch();onStatus({state:'unavailable'});}
  function clear(){generation++;session.remove();clearSamples();busy=false;phase='unregistered';}
  return {
    get registered(){return phase==='registered';},
    begin(){if(phase==='registering')return;clear();phase='registering';onStatus({state:'registering',samples:0});},
    async feed(pcm,meta){
      if(phase==='unregistered')return;
      if(!(pcm instanceof Float32Array)||pcm.length!==16000||!pcm.every(Number.isFinite)||!Number.isInteger(meta?.speechFrames)||meta.speechFrames<80||meta.speechFrames>100||meta.clipped!==false||!Number.isFinite(meta.startTime)||!Number.isFinite(meta.endTime)||Math.abs(meta.endTime-meta.startTime-1)>.001){onStatus({state:'quality',samples:samples.length});return;}
      if(phase==='registering'){
        if(busy)return;busy=true;const token=generation,owned=pcm.slice();
        try{
          if(!samples.length)onStatus({state:'loading',samples:0});
          const embedding=await embed(owned,()=>{if(token===generation)onStatus({state:'registering',samples:samples.length});});
          if(token!==generation){embedding?.fill?.(0);return;}
          if(!(embedding instanceof Float32Array)||!embedding.length||!embedding.every(Number.isFinite)||!embedding.some(x=>x!==0)||samples.some(x=>x.length!==embedding.length))throw Error('Invalid embedding');
          for(const previous of samples){let dot=0,a=0,b=0;for(let i=0;i<previous.length;i++){dot+=previous[i]*embedding[i];a+=previous[i]**2;b+=embedding[i]**2;}if(dot/Math.sqrt(a*b)<.43324563999132065){embedding.fill(0);onStatus({state:'quality',samples:samples.length});return;}}
          samples.push(embedding.slice());embedding.fill(0);
          if(samples.length<3){onStatus({state:'registering',samples:samples.length});return;}
          const mean=new Float32Array(samples[0].length);for(const sample of samples)for(let i=0;i<mean.length;i++)mean[i]+=sample[i]/samples.length;
          session.register(mean,{keepWorker:true});mean.fill(0);clearSamples();phase='registered';onStatus({state:'registered'});
        }catch{if(token===generation){clear();onStatus({state:'unavailable'});}}
        finally{owned.fill(0);if(token===generation)busy=false;}
      }else session.submit(pcm,{startTime:meta.startTime,endTime:meta.endTime,epoch});
    },
    resetEpoch(){generation++;epoch++;cancel();session.resetEpoch();clearSamples();busy=false;if(phase==='registering')phase='unregistered';onStatus({state:phase==='registered'?'confirming':'unregistered'});},
    remove(){clear();onStatus({state:'unregistered'});},
  };
}
