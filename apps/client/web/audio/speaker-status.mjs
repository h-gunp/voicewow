// Experimental one-second raw-VAD development-set thresholds; not identity proof.
const upper = .43324563999132065, lower = upper - .05;
export function speakerStatus({score,startTime,endTime,receivedTime,epoch,currentEpoch}) {
  if (![score,startTime,endTime,receivedTime].every(Number.isFinite) || score < -1 || score > 1 ||
      !Number.isSafeInteger(epoch) || epoch !== currentEpoch || startTime < 0 ||
      Math.abs(endTime-startTime-1) > .001 || receivedTime < endTime || receivedTime-endTime > 1) return {state:'unavailable'};
  return {state:score >= upper ? 'similar' : score < lower ? 'dissimilar' : 'uncertain',startTime,endTime,delayMs:(receivedTime-endTime)*1000,epoch};
}
