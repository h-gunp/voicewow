import { createProcessedRecorder } from '../audio/processed-capture.mjs';

// Bound browser pronunciation inference memory to ten seconds.
export function createRecorder(options = {}) {
  return createProcessedRecorder({...options, maxSeconds: 10});
}
