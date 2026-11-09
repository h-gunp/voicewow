import test from 'node:test';
import {execFileSync} from 'node:child_process';

test('both capture modes initialize when the worklet host forbids dynamic import', () => {
  const program = `
    import assert from 'node:assert/strict';
    import vm from 'node:vm';
    import {readFile} from 'node:fs/promises';
    import {pathToFileURL} from 'node:url';
    const context = vm.createContext({console, WebAssembly, TextDecoder, TextEncoder, URL, setTimeout, clearTimeout});
    const modules = new Map();
    async function load(url) {
      if (modules.has(url.href)) return modules.get(url.href);
      const source = await readFile(url, 'utf8');
      const module = new vm.SourceTextModule(source, {
        context, identifier: url.href,
        initializeImportMeta(meta) { meta.url = url.href; },
        importModuleDynamically() { throw new Error('AudioWorklet host does not support dynamic import'); },
      });
      modules.set(url.href, module);
      await module.link((specifier, parent) => load(new URL(specifier, parent.identifier)));
      return module;
    }
    const root = pathToFileURL(process.cwd() + '/');
    const module = await load(new URL('apps/client/web/audio/capture-processor.mjs', root));
    await module.evaluate();
    const create = module.namespace.createCaptureProcessor;
    const binary = new Uint8Array(await readFile(new URL('apps/client/web/audio/vendor/rnnoise/rnnoise.wasm', root)));
    const input = Float32Array.from({length: 960}, (_, i) => .1 * Math.sin(i * .17));
    for (const enabled of [true, false]) {
      const processor = await create(enabled ? binary : new Uint8Array([0]), {process: () => false, dispose() {}}, 48000, enabled);
      try {
        const frames = [...processor.push(input), ...processor.finish()];
        assert.equal(frames.reduce((sum, frame) => sum + frame.samples.length, 0), 960);
        if (!enabled) assert.deepEqual(frames.flatMap(frame => Array.from(frame.samples)), Array.from(input));
      } finally { processor.dispose(); }
    }
  `;
  execFileSync(process.execPath, ['--experimental-vm-modules', '--input-type=module', '-e', program], {cwd: new URL('../..', import.meta.url), stdio: 'pipe'});
});
