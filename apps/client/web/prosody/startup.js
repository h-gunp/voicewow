// Only the small shell loads first. Model workers remain behind their existing buttons.
export async function startProsody({ document = globalThis.document, window = globalThis.window,
  location = globalThis.location, load = () => import('./app.js') } = {}) {
  const content = document.getElementById('prosody-content');
  const status = document.getElementById('startup-status');
  const query = new URLSearchParams(location.search);
  const embedded = query.get('embedded') === '1';
  let active = true;
  const scaleText = scale => {
    if (typeof scale === 'number' && Number.isFinite(scale) && scale > 0) {
      document.documentElement.style.setProperty('--text-scale', String(scale));
    }
  };
  if (embedded) document.body.classList.add('embedded');
  scaleText(Number(query.get('textScale')) || 1);
  const onMessage = event => {
    if (event.origin === location.origin && event.source === window.parent
      && event.data?.type === 'voicemate:prosody:text-scale') {
      const scale = event.data.scale;
      scaleText(scale);
      if (typeof scale === 'number' && Number.isFinite(scale) && scale > 0) {
        const url = new URL(location.href);
        url.searchParams.set('textScale', String(scale));
        window.history.replaceState(window.history.state, '', url.toString());
      }
    }
  };
  const onPageHide = event => {
    if (event.persisted) return;
    active = false;
    window.removeEventListener('message', onMessage);
    window.removeEventListener('pagehide', onPageHide);
  };
  window.addEventListener('message', onMessage);
  window.addEventListener('pagehide', onPageHide);
  const notify = type => { if (embedded) window.parent.postMessage({ type }, location.origin); };
  try {
    await load();
    if (!active) return false;
    content.inert = false;
    content.removeAttribute('aria-busy');
    status.hidden = true;
    notify('voicemate:prosody:ready');
    return true;
  } catch {
    if (!active) return false;
    status.textContent = '연습 화면을 불러오지 못했다. 연결을 확인하고 화면을 다시 불러오면 된다.';
    notify('voicemate:prosody:error');
    return false;
  }
}
