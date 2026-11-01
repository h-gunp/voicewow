import * as ort from './vendor/speaker/ort.wasm.bundle.min.mjs';
import {createSpeakerEngine} from './speaker-engine.mjs';
import {loadSpeakerModel} from './speaker-model.mjs';

ort.env.wasm.numThreads = 1;
let engine;
self.onmessage = async ({data}) => {
  const {id,value} = data;
  try {
    engine ??= await loadSpeakerModel({
      fetchPart:index=>fetch(new URL(`./vendor/speaker/voxceleb_resnet34.onnx.part${index+1}`,import.meta.url)),
      digest:bytes=>crypto.subtle.digest('SHA-256',bytes),
      create:bytes=>createSpeakerEngine(ort,bytes),
    });
    self.postMessage({id,phase:'inference'});
    const embedding = await engine.embed(value);
    self.postMessage({id,result:embedding});
    embedding.fill(0);
  } catch { self.postMessage({id,error:true}); }
  finally { value?.fill?.(0); }
};
