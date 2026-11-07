import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

export const UPSTREAM_SHA256 = '69751720f611e37d1ce2fa3c6ebaa80f949014752636c5f8887a63d40feadcc7';
const upstream = new URL('../../apps/client/web/prosody/vendor/onnx/', import.meta.url);
const destination = new URL('../../apps/client/web/pronunciation/vendor/onnx/', import.meta.url);
const sha256 = value => createHash('sha256').update(value).digest('hex');

export function patchRuntime(source) {
  source = source.replace(/\r\n/g, '\n');
  assert.equal(sha256(source), UPSTREAM_SHA256, 'Unexpected upstream ORT runtime; review the patch before upgrading');
  const replaceOnce = (before, after) => {
    assert.equal(source.split(before).length, 2, 'Runtime patch must match exactly once');
    source = source.replace(before, after);
  };
  replaceOnce('let a=0,i=0,s=0,u=[],f=[],c=[];try{', `let a=0,i=0,s=0,u=[],f=[],c=[];try{
    if(t?.extra?.session?.use_ort_model_bytes_for_initializers==="1"&&t?.extra?.session?.voicemate_consume_model_bytes==="1"&&e instanceof Uint8Array){
      const inputBuffer=e.buffer;
      if(inputBuffer instanceof ArrayBuffer&&inputBuffer!==r.HEAPU8.buffer&&e.byteOffset===0&&e.byteLength===inputBuffer.byteLength&&typeof inputBuffer.transfer==="function"){
        try{inputBuffer.transfer(0);}catch{/* Transfer support is optional; keep the original input on failure. */}
      }
    }
  `);
  replaceOnce('return ae.set(a,[a,f,c,null,p,!1]),[a,w,b,A,m]',
    'return ae.set(a,[a,f,c,null,p,!1]),t?.extra?.session?.use_ort_model_bytes_for_initializers==="1"&&pronunciationModelBuffers.set(a,n),[a,w,b,A,m]');
  replaceOnce('finally{r._free(n),i!==0&&r._OrtReleaseSessionOptions(i)!==0&&T("Can\'t release session options."),u.forEach(l=>r._free(l)),r.unmountExternalData?.()}', `finally{
    try{
      i!==0&&r._OrtReleaseSessionOptions(i)!==0&&T("Can't release session options.");
      u.forEach(l=>r._free(l));r.unmountExternalData?.();
    }catch(error){
      if(ae.has(a)){ae.delete(a);pronunciationModelBuffers.delete(a);r._OrtReleaseSession(a);}
      throw error;
    }finally{if(pronunciationModelBuffers.get(a)!==n)r._free(n);}
  }`);
  const releaseStart = source.indexOf('De=e=>{let t=I(),n=ae.get(e);');
  const releaseEnd = source.indexOf(',dn=async', releaseStart);
  assert.ok(releaseStart >= 0 && releaseEnd > releaseStart);
  source = source.slice(0, releaseStart) + `De=e=>{
    const t=I(),n=ae.get(e);
    if(!n)throw new Error(\`cannot release session. invalid session id: \${e}\`);
    const[o,r,a,i,s]=n;
    try{
      try{
        i&&(s&&t._OrtClearBoundOutputs(i.handle)!==0&&T("Can't clear bound outputs."),t._OrtReleaseBinding(i.handle)!==0&&T("Can't release IO binding."));
        t.jsepOnReleaseSession?.(e);t.webnnOnReleaseSession?.(e);t.webgpuOnReleaseSession?.(e);
        r.forEach(u=>t._OrtFree(u));a.forEach(u=>t._OrtFree(u));
      }finally{t._OrtReleaseSession(o)!==0&&T("Can't release session.");}
    }finally{
      ae.delete(e);
      const pointer=pronunciationModelBuffers.get(e);
      pronunciationModelBuffers.delete(e);
      if(pointer!==undefined)t._free(pointer);
    }
  }` + source.slice(releaseEnd);
  return '// Direct ORT initializers borrow this WASM buffer until session release.\nconst pronunciationModelBuffers=new Map();\n' + source;
}

async function main() {
  assert.ok(process.argv.length <= 3 && (!process.argv[2] || process.argv[2] === '--check'), 'Usage: node tools/pronunciation-spike/patch-runtime.mjs [--check]');
  const original = await readFile(new URL('ort.wasm.min.mjs', upstream), 'utf8');
  const patched = patchRuntime(original);
  const license = (await readFile(new URL('LICENSE.txt', upstream), 'utf8')).replace(/\r\n/g, '\n');
  const source = JSON.stringify({
    package: 'onnxruntime-web', version: '1.23.2',
    upstreamDistUrl: 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.23.2/dist/ort.wasm.min.mjs',
    upstreamSourceUrl: 'https://github.com/microsoft/onnxruntime/blob/v1.23.2/js/web/lib/wasm/wasm-core-impl.ts',
    upstreamLocalFile: 'apps/client/web/prosody/vendor/onnx/ort.wasm.min.mjs',
    upstreamSha256: UPSTREAM_SHA256,
    patchedSha256: sha256(patched),
    generator: 'tools/pronunciation-spike/patch-runtime.mjs',
    patchScope: 'Retain WASM model bytes for successful direct-initializer sessions; free once on release, including failed cleanup; optionally consume an exclusively owned whole input after copying to WASM; ordinary sessions keep immediate-free behavior.',
    consumeModelBytesContract: 'extra.session.voicemate_consume_model_bytes="1" promises sole ownership of the supplied model buffer after validation and completed cache writes. Consumption also requires use_ort_model_bytes_for_initializers="1", an entire nonshared ArrayBuffer view, and working ArrayBuffer.transfer. The input may be detached even if later session creation fails. Shared/subarray inputs and unsupported transfer retain the existing path.',
    license: 'MIT', licenseSha256: sha256(license),
    sharedWasmAssets: '../../../prosody/vendor/onnx/',
    thirdPartyNotices: '../../../prosody/vendor/onnx/ThirdPartyNotices.txt',
    notes: 'Pronunciation-only JavaScript runtime. Set env.wasm.wasmPaths explicitly to the shared upstream WASM directory. No WASM binary changes or duplicated weights.',
  }, null, 2) + '\n';
  const files = [['ort.wasm.min.mjs', patched], ['source.json', source], ['LICENSE.txt', license]];
  if (process.argv[2] === '--check') {
    for (const [name, expected] of files) assert.equal(await readFile(new URL(name, destination), 'utf8'), expected, `Stale runtime artifact: ${name}`);
    console.log('Pronunciation runtime artifacts match the pinned upstream and patch.');
  } else {
    await mkdir(fileURLToPath(destination), { recursive: true });
    for (const [name, content] of files) await writeFile(new URL(name, destination), content);
    console.log('Generated pronunciation-only runtime artifacts.');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) await main();
