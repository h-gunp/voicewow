// PCM jobs use Float32Array; scalar messages are reserved for worker controls.
export function createSpeakerSession({run, onResult, onError = () => {}, cancel = () => {}}) {
  let profile = null, revision = 0, epoch = 0, busy = false, queued = null;
  function discardQueued() { if (queued?.value instanceof Float32Array) queued.value.fill(0); queued = null; }
  function pump(job) {
    busy = true;
    const {value, metadata, profile: currentProfile, revision: currentRevision, epoch: currentEpoch} = job;
    Promise.resolve().then(() => {
      if (profile === null || revision !== currentRevision || epoch !== currentEpoch) return;
      return run(value, currentProfile, metadata);
    }).then(result => {
      if (profile !== null && revision === currentRevision && epoch === currentEpoch) onResult(result, metadata);
    }, error => {
      if (profile !== null && revision === currentRevision && epoch === currentEpoch) onError(error);
    }).finally(() => {
      if (value instanceof Float32Array) value.fill(0);
      busy = false;
      const next = queued; queued = null;
      if (next) pump(next);
    });
  }
  return {
    get registered() { return profile !== null; },
    register(value, {keepWorker = false} = {}) { if (!(value instanceof Float32Array) || !value.length || !value.every(Number.isFinite)) throw new TypeError('finite profile required'); revision++; discardQueued(); if (!keepWorker) cancel(); profile?.fill(0); profile = value.slice(); },
    remove() { revision++; discardQueued(); cancel(); profile?.fill(0); profile = null; },
    resetEpoch() { epoch++; discardQueued(); cancel(); },
    submit(value, metadata = null) {
      if (profile === null) return false;
      if (!(value instanceof Float32Array) && !['string','number','boolean'].includes(typeof value)) throw new TypeError('PCM or scalar control required');
      const job = {value: value instanceof Float32Array ? value.slice() : value, metadata: metadata === null ? null : {...metadata}, profile, revision, epoch};
      if (busy) { discardQueued(); queued = job; } else pump(job);
      return true;
    },
  };
}
