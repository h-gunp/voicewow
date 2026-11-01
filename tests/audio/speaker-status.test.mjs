import test from 'node:test';import assert from 'node:assert/strict';
import {speakerStatus} from '../../apps/client/web/audio/speaker-status.mjs';
const base={score:.5,startTime:1,endTime:2,receivedTime:2.2,epoch:3,currentEpoch:3};
test('experimental status identifies its own one-second window and delay',()=>{
 const a=speakerStatus(base);assert.equal(a.state,'similar');assert.equal(a.startTime,1);assert.equal(a.endTime,2);assert.ok(Math.abs(a.delayMs-200)<1e-8);
 assert.equal(speakerStatus({...base,score:.4}).state,'uncertain');
 assert.equal(speakerStatus({...base,score:.2}).state,'dissimilar');
});
test('stale, wrong epoch and invalid times or scores never produce identity',()=>{
 for(const x of [{...base,currentEpoch:4},{...base,receivedTime:4},{...base,startTime:1.1},{...base,score:NaN},{...base,receivedTime:1.9}])assert.equal(speakerStatus(x).state,'unavailable');
});
