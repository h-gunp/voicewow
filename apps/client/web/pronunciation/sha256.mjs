import './vendor/hash-wasm/sha256.umd.min.js';

// WebCrypto digest copies its entire input; keep the extra workspace bounded for mobile.
export async function sha256(input) {
  const bytes = input instanceof ArrayBuffer ? new Uint8Array(input) : input;
  if (!(bytes instanceof Uint8Array)) throw new TypeError('Expected model bytes');
  const hash = await globalThis.hashwasm.createSHA256();
  for (let offset = 0; offset < bytes.length; offset += 262144) {
    hash.update(bytes.subarray(offset, offset + 262144));
  }
  return hash.digest('hex');
}
