const width=19,weights=Float32Array.from({length:41},(_,n)=>{let t=Math.max(-6,Math.min(6,(n-width)/3*.99));const win=Math.cos(t*Math.PI/12)**2;t*=Math.PI;return (t===0?1:Math.sin(t)/t)*win*.33;});
export function createSpeakerResampler(){
 let samples=[],start=0,total=0,next=0;
 function drain(finished){const out=[];while(next<Math.ceil(total/3)&&(finished||3*next+21<total)){
  let v=0;for(let k=0;k<41;k++){const i=3*next+k-width;if(i>=0&&i<total)v+=samples[i-start]*weights[k];}out.push(v);next++;
 }const retain=Math.max(0,3*next-width),drop=Math.min(samples.length,Math.max(0,retain-start));samples.fill(0,0,drop);samples.splice(0,drop);start+=drop;return out;}
 function reset(){samples.fill(0);samples=[];start=total=next=0;}
 return {push(input){for(const x of input){if(!Number.isFinite(x))throw Error('invalid sample');samples.push(x);total++;}return drain(false);},finish(){const out=drain(true);reset();return out;},reset};
}
