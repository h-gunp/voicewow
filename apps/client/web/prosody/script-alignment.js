// Local ASR text evidence only: no audio, network, pronunciation score or timing.
export function indexedText(text) {
  const units=[];
  for(const {segment,index} of new Intl.Segmenter('ko',{granularity:'grapheme'}).segment(text)) {
    for(const char of segment.normalize('NFC').toLocaleLowerCase('ko')) {
      if(/[\p{L}\p{N}]/u.test(char)) units.push({char,start:index,end:index+segment.length});
    }
  }
  return units;
}

// Map generated practice chunks sequentially, so repeated sentences retain their
// distinct original offsets. Never reconstruct the source from normalized text.
export function sourceRanges(source, chunks) {
  const units=indexedText(source), ranges=[];
  let cursor=0;
  for(const chunk of chunks) {
    const target=indexedText(chunk).map(x=>x.char);
    if(!target.length) throw new Error('Empty practice chunk');
    while(cursor<units.length&&units[cursor].char!==target[0]) cursor++;
    if(!target.every((char,i)=>units[cursor+i]?.char===char)) throw new Error('Practice source changed');
    ranges.push({start:units[cursor].start,end:units[cursor+target.length-1].end});
    cursor+=target.length;
  }
  return ranges;
}

/** Finds the latest unique EXACT supported block, even if the recognizer got
 * later words wrong. Mismatches are never highlighted. `uncertain-tail` means
 * the returned block is earlier evidence, NOT the current speaking position.
 * Repeated phrases remain ambiguous unless the user selected a narrower scope.
 */
export function locateScript(source,hypothesis,{scope={start:0,end:source?.length}}={}) {
  if(typeof source!=='string'||typeof hypothesis!=='string') throw new TypeError('Expected text');
  if(source.length>8000||hypothesis.length>8000) throw new RangeError('Text too long');
  if(!Number.isInteger(scope.start)||!Number.isInteger(scope.end)||scope.start<0||scope.end>source.length||scope.start>=scope.end)
    throw new RangeError('Invalid source range');
  const script=indexedText(source).filter(x=>x.start>=scope.start&&x.end<=scope.end);
  const heard=indexedText(hypothesis).slice(-160);
  if(heard.length<6) return {status:'insufficient',range:null};
  let previous=new Uint16Array(script.length+1), bestEnd=-1, bestSize=0, candidates=[];
  for(let h=0;h<heard.length;h++) {
    const row=new Uint16Array(script.length+1);
    for(let s=0;s<script.length;s++) {
      if(heard[h].char!==script[s].char) continue;
      const size=row[s+1]=previous[s]+1;
      if(size<6) continue;
      if(h>bestEnd||(h===bestEnd&&size>bestSize)) {bestEnd=h;bestSize=size;candidates=[s];}
      else if(h===bestEnd&&size===bestSize) candidates.push(s);
    }
    previous=row;
  }
  if(!candidates.length) return {status:'uncertain',range:null};
  // Check repeated copies of the chosen block anywhere in the selected source,
  // including shorter runs caused by different preceding context.
  const block=heard.slice(bestEnd-bestSize+1,bestEnd+1).map(x=>x.char);
  const occurrences=[];
  for(let s=0;s<=script.length-block.length;s++) {
    if(block.every((char,i)=>script[s+i].char===char)) occurrences.push(s);
  }
  if(occurrences.length!==1) return {status:'ambiguous',range:null};
  const first=occurrences[0], start=script[first].start,end=script[first+bestSize-1].end;
  const trailingUnmatched=heard.length-1-bestEnd;
  return {status:trailingUnmatched?'uncertain-tail':'matched',range:{start,end},
    text:source.slice(start,end),before:source.slice(scope.start,start),after:source.slice(end,scope.end),
    matchedCharacters:bestSize,trailingUnmatched};
}

/** Partial ASR hypotheses must survive a newer audio observation before being
 * shown as stable text evidence. This is a heuristic, not calibrated confidence.
 * Revisions, endpoint/session resets, silence and low evidence clear the mark.
 */
export class ScriptTracker {
  constructor(source,scope) {this.source=source;this.scope=scope;this.reset();}
  reset() {this.previous=null;this.lastSequence=-1;}
  update({text,sequence,final=false}) {
    if(!Number.isSafeInteger(sequence)||sequence<=this.lastSequence) return {status:'stale',range:null};
    this.lastSequence=sequence;
    const result=locateScript(this.source,text,{scope:this.scope});
    const old=this.previous;
    this.previous=result;
    if(!result.range) return result;
    const stable=final===true||(old?.range&&old.range.start===result.range.start&&old.range.end<=result.range.end);
    return stable?{...result,evidence:final===true?'endpoint':'stable-partial'}:{status:'tentative',range:null};
  }
}
