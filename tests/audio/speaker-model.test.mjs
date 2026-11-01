import test from 'node:test';
import assert from 'node:assert/strict';
import {loadSpeakerModel} from '../../apps/client/web/audio/speaker-model.mjs';

test('model loader rejects HTTP errors and wrong hash before inference, then retries',async()=>{
 let requests=0,created=0,correct=false;
 const load=()=>loadSpeakerModel({fetchModel:async()=>({ok:++requests!==1,arrayBuffer:async()=>new Uint8Array([1]).buffer}),digest:async()=>new Uint8Array(correct?[0x9f,0xea,0x65,0x16,0xd7,0xad,0x6b,0xf0,0xa7,0x6c,0x76,0x89,0xf5,0xa4,0x9b,0x65,0xd3,0x30,0xfa,0xd6,0xdd,0xe9,0x6c,0x91,0xbb,0x44,0x35,0xff,0xbf,0xe0,0x56,0xa1]:[0]).buffer,create:async()=>{created++;return 'engine';}});
 await assert.rejects(load(),/HTTP/);await assert.rejects(load(),/hash/);assert.equal(created,0);
 correct=true;assert.equal(await load(),'engine');assert.equal(created,1);assert.equal(requests,3);
});
