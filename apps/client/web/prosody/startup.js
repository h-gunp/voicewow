// Standalone entry; the Flutter app mounts the same factory directly.
export async function startProsody({ document = globalThis.document, window = globalThis.window,
  load = () => import('./app.js') } = {}) {
  const content = document.getElementById('prosody-content');
  const status = document.getElementById('startup-status');
  let active = true;
  const onPageHide = event => { if (!event.persisted) active = false; };
  window.addEventListener('pagehide', onPageHide);
  try {
    const { createProsodyApp } = await load();
    if (!active) return false;
    createProsodyApp({ document, window });
    content.inert = false;
    content.removeAttribute('aria-busy');
    status.hidden = true;
    return true;
  } catch {
    if (!active) return false;
    status.textContent = '연습 화면을 불러오지 못했다. 연결을 확인하고 화면을 다시 불러오면 된다.';
    return false;
  } finally {
    window.removeEventListener('pagehide', onPageHide);
  }
}
