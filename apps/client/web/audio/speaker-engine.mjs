import {speakerFbank} from './speaker-fbank.mjs';

function norm(vector) {
  if (!(vector instanceof Float32Array) || !vector.length || !vector.every(Number.isFinite)) throw new RangeError('Invalid embedding');
  let sum=0;for(const value of vector)sum+=value*value;
  if (!Number.isFinite(sum) || sum <= 0) throw new RangeError('Invalid embedding');
  return Math.sqrt(sum);
}

// Caller supplies the local runtime and model; this module never fetches data.
export async function createSpeakerEngine(ort, binary) {
  const session=await ort.InferenceSession.create(binary,{executionProviders:['wasm']});
  let disposed=false;
  return {
    async embed(pcm) {
      if(disposed)throw Error('Speaker engine disposed');
      const rows=speakerFbank(pcm), features=Float32Array.from(rows.flat());
      try {
        const output=await session.run({[session.inputNames[0]]:new ort.Tensor('float32',features,[1,rows.length,80])});
        if(disposed)throw Error('Speaker engine disposed');
        const vector=output[session.outputNames[0]]?.data, length=norm(vector);
        return Float32Array.from(vector,value=>value/length);
      } finally {features.fill(0);for(const row of rows)row.fill(0);}
    },
    similarity(a,b) {
      if(disposed)throw Error('Speaker engine disposed');
      if(a.length!==b.length)throw new RangeError('Invalid embedding dimensions');
      const denominator=norm(a)*norm(b);let dot=0;for(let i=0;i<a.length;i++)dot+=a[i]*b[i];return dot/denominator;
    },
    async dispose() {if(disposed)return;disposed=true;await session.release();},
  };
}
