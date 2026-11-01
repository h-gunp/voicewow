// 16 kHz mono PCM with the pinned WeSpeaker/Kaldi fbank settings.
export function speakerFbank(pcm) {
  if (!(pcm instanceof Float32Array) || pcm.length < 400) throw new RangeError('At least 400 samples required');
  if (!pcm.every(Number.isFinite)) throw new RangeError('Samples must be finite');
  const frames=Math.max(0,Math.floor((pcm.length-400)/160)+1), output=[], bins=80;
  const mel=f=>1127*Math.log(1+f/700), low=mel(20), step=(mel(8000)-low)/81;
  const filters=Array.from({length:bins},(_,b)=>Float64Array.from({length:256},(_,k)=>{
    const m=mel(k*16000/512);return Math.max(0,Math.min((m-low-b*step)/step,(low+(b+2)*step-m)/step));
  }));
  for(let frame=0;frame<frames;frame++){
    const samples=new Float64Array(512); let mean=0;
    for(let i=0;i<400;i++){samples[i]=Math.fround(pcm[frame*160+i]*32768);mean+=samples[i];}mean/=400;
    for(let i=0;i<400;i++)samples[i]-=mean;
    for(let i=399;i>=0;i--)samples[i]=(samples[i]-.97*samples[Math.max(0,i-1)])*(.54-.46*Math.cos(2*Math.PI*i/399));
    const real=samples,imag=new Float64Array(512);
    for(let i=1,j=0;i<512;i++){let bit=256;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)[real[i],real[j]]=[real[j],real[i]];}
    for(let size=2;size<=512;size*=2){const half=size/2;for(let start=0;start<512;start+=size)for(let j=0;j<half;j++){
      const a=-2*Math.PI*j/size,c=Math.cos(a),s=Math.sin(a),k=start+j,l=k+half,tr=c*real[l]-s*imag[l],ti=s*real[l]+c*imag[l];
      real[l]=real[k]-tr;imag[l]=imag[k]-ti;real[k]+=tr;imag[k]+=ti;
    }}
    const power=Float64Array.from({length:256},(_,k)=>real[k]*real[k]+imag[k]*imag[k]);
    output.push(Array.from(filters,f=>{let energy=0;for(let k=0;k<256;k++)energy+=f[k]*power[k];return Math.log(Math.max(energy,2**-23));}));
  }
  for(let b=0;b<bins;b++){let mean=0;for(const row of output)mean+=row[b];mean/=frames;for(const row of output)row[b]-=mean;}
  return output;
}
