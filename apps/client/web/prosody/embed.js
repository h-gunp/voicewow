const templateUrl = new URL('./index.html', import.meta.url);
const stylesheetUrl = new URL('./styles.css', import.meta.url);

// The app receives only its own DOM, while visibility and element creation still
// belong to the real document. No page-wide styles, history or globals change.
function scopedDocument(root, body, host) {
  const owner = host.ownerDocument;
  return {
    body,
    documentElement: host,
    get activeElement() { return root.activeElement; },
    get hidden() { return owner.hidden; },
    getElementById: id => root.getElementById(id),
    querySelector: selector => root.querySelector(selector),
    querySelectorAll: selector => root.querySelectorAll(selector),
    createElement: tag => owner.createElement(tag),
    addEventListener: (...args) => owner.addEventListener(...args),
    removeEventListener: (...args) => owner.removeEventListener(...args),
  };
}

export function createProsodySurface(host, onExit, { loadApp = () => import('./app.js') } = {}) {
  const owner = host.ownerDocument, window = owner.defaultView;
  const root = host.shadowRoot || host.attachShadow({ mode: 'open' });
  const wrapper = owner.createElement('div');
  wrapper.className = 'prosody-root embedded';
  wrapper.inert = true;
  const stylesheet = owner.createElement('link');
  stylesheet.rel = 'stylesheet';
  stylesheet.href = stylesheetUrl.href;
  const controller = new AbortController();
  let app = null, disposed = false, paused = false, settled = false;
  let resolveReady, rejectReady, stopStylesheet;
  const ready = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
  const reject = error => {
    if (settled) return;
    settled = true;
    rejectReady(error);
  };
  const updateSize = entries => {
    if (disposed) return;
    const rect = entries?.find(entry => entry.target === host)?.contentRect || host.getBoundingClientRect();
    if (rect.height > 0) {
      host.style.setProperty('--surface-height', `${rect.height}px`);
      wrapper.classList.toggle('small-height', rect.height <= 500);
    }
    app?.resize();
  };
  const observer = new window.ResizeObserver(updateSize);
  const stylesReady = new Promise((resolve, rejectStyles) => {
    const onLoad = () => { stopStylesheet(); resolve(); };
    const onError = () => { stopStylesheet(); rejectStyles(new Error('Prosody stylesheet could not be loaded.')); };
    stopStylesheet = () => {
      stylesheet.removeEventListener('load', onLoad);
      stylesheet.removeEventListener('error', onError);
    };
    stylesheet.addEventListener('load', onLoad);
    stylesheet.addEventListener('error', onError);
  });

  function dispose() {
    if (disposed) return;
    disposed = true;
    reject(new DOMException('The prosody surface was disposed.', 'AbortError'));
    controller.abort();
    stopStylesheet();
    observer.disconnect();
    try { app?.dispose(); }
    finally { app = null; stylesheet.remove(); wrapper.remove(); }
  }

  const surface = {
    ready,
    pause() { if (!disposed) { paused = true; app?.pause(); } },
    dispose,
    setTextScale(scale) {
      if (disposed || typeof scale !== 'number' || !Number.isFinite(scale) || scale <= 0) return;
      host.style.setProperty('--text-scale', String(scale));
      app?.resize();
    },
  };

  root.append(stylesheet, wrapper);
  observer.observe(host);
  updateSize();

  async function initialize() {
    const html = window.fetch(templateUrl.href, { signal: controller.signal }).then(async response => {
      if (!response.ok) throw new Error('Prosody template could not be loaded.');
      return response.text();
    });
    const [source, module] = await Promise.all([html, loadApp(), stylesReady]);
    if (disposed) return;
    const parsed = new window.DOMParser().parseFromString(source, 'text/html');
    const template = parsed.getElementById('prosody-content');
    if (!template) throw new Error('Prosody content is missing.');
    const content = owner.importNode(template, true);
    for (const element of content.querySelectorAll('[href], [src]')) {
      for (const attribute of ['href', 'src']) {
        if (element.hasAttribute(attribute)) {
          element.setAttribute(attribute, new URL(element.getAttribute(attribute), templateUrl).href);
        }
      }
    }
    wrapper.append(content);
    app = module.createProsodyApp({
      document: scopedDocument(root, wrapper, host), window, embedded: true, onExit,
    });
    if (paused) app.pause();
    updateSize();
    content.inert = false;
    content.removeAttribute('aria-busy');
    wrapper.inert = false;
    settled = true;
    resolveReady();
  }
  initialize().catch(error => { reject(error); dispose(); });
  return surface;
}
