import { createPhoneClient as createProductClient } from '../../apps/client/web/pronunciation/client.mjs';

// The offline verification page uses its allowlisted .local assets.
export function createPhoneClient() {
  return createProductClient({ workerUrl: new URL('./worker.mjs', import.meta.url) });
}