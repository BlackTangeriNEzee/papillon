(() => {
  let host;
  let shadow;
  let button;
  let bubble;
  let selectedText = '';
  let selectionRect = null;
  let openedAt = null;
  let requestId = 0;
  let ui;
  let pageActive = false;
  let pageRunId = 0;
  let pagePillHost;
  let pagePill;
  let pagePillTimer;
  const pageBlocks = new Set();
  const pageTranslations = new Set();

  function collectBlocks(root) {
    const selector = 'p, li, h1, h2, h3, h4, h5, h6, blockquote, dd, dt, td, th, figcaption, caption, summary, div, section, article';
    const excludedTags = ['SCRIPT', 'STYLE', 'CODE', 'PRE', 'NAV', 'HEADER', 'FOOTER', 'ASIDE', 'FORM', 'BUTTON', 'LABEL', 'SELECT', 'OPTION'];
    const excludedRoles = ['navigation', 'banner', 'menu', 'menubar', 'toolbar', 'search'];
    const blocks = [];
    for (const element of root.querySelectorAll(selector)) {
      let excluded = false;
      for (let ancestor = element; ancestor; ancestor = ancestor.parentElement) {
        if (excludedTags.includes(ancestor.tagName) || excludedRoles.includes(ancestor.getAttribute('role')) ||
            ancestor.getAttribute('aria-hidden') === 'true' ||
            ancestor.isContentEditable || ancestor.getAttribute('translate') === 'no' ||
            ancestor.id === 'zhaocai-ui-host' || ancestor.id === 'zhaocai-page-status-host' ||
            ancestor.classList?.contains('zhaocai-translation')) {
          excluded = true;
          break;
        }
      }
      if (excluded || element.hasAttribute('data-zhaocai-translated') ||
          !element.getClientRects().length || element.checkVisibility?.({ checkOpacity: true, checkVisibilityCSS: true }) === false) continue;
      const style = getComputedStyle(element);
      if (['absolute', 'fixed'].includes(style.position) ||
          ['inline', 'inline-block', 'inline-flex', 'inline-grid'].includes(style.display) ||
          element.getBoundingClientRect().width < 40) continue;
      const hasNestedCandidate = Boolean(element.querySelector(selector));
      const text = hasNestedCandidate
        ? Array.from(element.childNodes).filter(node => node.nodeType === 3).map(node => node.textContent.trim()).filter(Boolean).join(' ')
        : element.innerText?.trim() || '';
      if (hasNestedCandidate && text.length < 6 && text.split(/\s+/).length < 2) continue;
      if (text.length < 2 || /^[A-Za-z]$/.test(text) || (text.match(/[A-Za-z\u3400-\u9fff\uf900-\ufaff]/g) || []).length < 2) continue;
      blocks.push({ element, text });
    }
    return blocks;
  }

  function showPagePill(text, error = false) {
    clearTimeout(pagePillTimer);
    if (!pagePillHost?.isConnected) {
      pagePillHost = document.createElement('div');
      pagePillHost.id = 'zhaocai-page-status-host';
      const statusShadow = pagePillHost.attachShadow({ mode: 'open' });
      const style = document.createElement('style');
      style.textContent = ':host{position:fixed;right:16px;bottom:16px;z-index:2147483647;pointer-events:none}.pill{display:block;max-width:min(360px,calc(100vw - 32px));padding:7px 12px;border-radius:999px;background:#302e2a;color:#fff;box-shadow:0 3px 14px #0004;font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;overflow-wrap:anywhere}.pill.error{background:#a9362e}';
      statusShadow.appendChild(style);
      pagePill = document.createElement('div');
      pagePill.className = 'pill';
      pagePill.setAttribute('role', 'status');
      pagePill.setAttribute('aria-live', 'polite');
      statusShadow.appendChild(pagePill);
      document.documentElement.appendChild(pagePillHost);
    }
    pagePill.className = error ? 'pill error' : 'pill';
    pagePill.textContent = text;
  }

  function restorePage() {
    pageActive = false;
    pageRunId += 1;
    clearTimeout(pagePillTimer);
    for (const translation of pageTranslations) translation.remove();
    for (const block of pageBlocks) block.removeAttribute('data-zhaocai-translated');
    pageTranslations.clear();
    pageBlocks.clear();
    pagePillHost?.remove();
  }

  async function translatePage() {
    if (pageActive) { restorePage(); return; }
    pageActive = true;
    const runId = ++pageRunId;
    const candidates = collectBlocks(document.body);
    const language = document.documentElement.lang.toLowerCase();
    const toChinese = language ? !language.startsWith('zh') :
      candidates.filter(({ text }) => /[\u3400-\u9fff\uf900-\ufaff]/.test(text)).length <= candidates.length / 2;
    const blocks = candidates.filter(({ text }) => toChinese ? !/[\u3400-\u9fff\uf900-\ufaff]/.test(text) : /[\u3400-\u9fff\uf900-\ufaff]/.test(text));
    const { uiLanguage = 'system' } = await chrome.storage.local.get('uiLanguage');
    if (runId !== pageRunId) return;
    const chinese = uiLanguage === 'zh' || (uiLanguage === 'system' && navigator.language.startsWith('zh'));
    const progress = count => chinese ? `翻译中 ${count}/${blocks.length}` : `Translating ${count}/${blocks.length}`;
    showPagePill(progress(0));
    let done = 0;
    let next = 0;
    let failed = false;
    const worker = async () => {
      while (next < blocks.length && !failed && runId === pageRunId) {
        const batch = blocks.slice(next, next + 20);
        next += batch.length;
        try {
          const reply = await chrome.runtime.sendMessage({ type: 'translateTexts', texts: batch.map(({ text }) => text) });
          if (runId !== pageRunId || failed) return;
          if (!reply?.ok) throw new Error(reply?.error || (chinese ? '翻译失败' : 'Translation failed'));
          if (!Array.isArray(reply.result?.texts) || reply.result.texts.length !== batch.length) throw new Error(chinese ? '译文数量不匹配' : 'Translation count mismatch');
          batch.forEach(({ element }, index) => {
            if (!element.isConnected || element.hasAttribute('data-zhaocai-translated')) return;
            const translation = document.createElement('div');
            translation.className = 'zhaocai-translation';
            translation.setAttribute('translate', 'no');
            translation.textContent = reply.result.texts[index];
            translation.style.fontSize = getComputedStyle(element).fontSize;
            if (['LI', 'TD', 'TH', 'DT', 'DD', 'SUMMARY', 'FIGCAPTION', 'CAPTION'].includes(element.tagName) ||
                ['UL', 'OL', 'DL', 'TR', 'TABLE', 'TBODY', 'THEAD', 'TFOOT'].includes(element.parentElement?.tagName)) element.append(translation);
            else element.after(translation);
            element.setAttribute('data-zhaocai-translated', '');
            pageBlocks.add(element);
            pageTranslations.add(translation);
          });
          done += batch.length;
          showPagePill(progress(done));
        } catch (error) {
          if (runId !== pageRunId) return;
          failed = true;
          showPagePill(error.message, true);
        }
        await new Promise(resolve => setTimeout(resolve, 0));
      }
    };
    await Promise.all([worker(), worker()]);
    if (runId === pageRunId && !failed) {
      showPagePill(chinese ? `翻译完成 ${done}/${blocks.length}` : `Translated ${done}/${blocks.length}`);
      pagePillTimer = setTimeout(() => { if (runId === pageRunId) pagePillHost?.remove(); }, 2000);
    }
  }

  function selection() {
    const value = window.getSelection();
    const text = value?.toString().trim() || '';
    if (!text || !value.rangeCount) return null;
    const range = value.getRangeAt(0).cloneRange();
    range.collapse(false);
    const rect = range.getBoundingClientRect();
    const bounds = value.getRangeAt(0).getBoundingClientRect();
    return { text, rect: rect.width || rect.height ? rect : bounds };
  }

  function ensureHost() {
    if (host?.isConnected) return;
    host = document.createElement('div');
    host.id = 'zhaocai-ui-host';
    shadow = host.attachShadow({ mode: 'open' });
    for (const path of ['lib/theme.css', 'popup.css']) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = chrome.runtime.getURL(path);
      shadow.appendChild(link);
    }
    const style = document.createElement('style');
    style.textContent = '.selection-button{position:fixed;pointer-events:auto;width:30px;height:30px;padding:0;border:1px solid var(--border);border-radius:50%;background:var(--surface);color:var(--accent);box-shadow:0 3px 12px #0003;font:600 17px Georgia,serif;cursor:pointer}.selection-button[hidden],.bubble[hidden]{display:none}.bubble{position:fixed;pointer-events:auto;width:min(380px,calc(100vw - 16px));max-height:min(70vh,600px);overflow:auto;padding:12px;border:1px solid var(--border);border-radius:16px;background:var(--background);color:var(--text);box-shadow:0 12px 35px #0004;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.bubble-content{display:grid;gap:9px}.bubble .card{min-width:0}.bubble .paragraph{line-height:1.6}.bubble .result-head{align-items:center}';
    shadow.appendChild(style);
    button = document.createElement('button');
    button.className = 'selection-button';
    button.type = 'button';
    button.textContent = '↔';
    button.hidden = true;
    button.addEventListener('mousedown', event => event.preventDefault());
    button.addEventListener('click', () => openBubble(selectedText, selectionRect));
    shadow.appendChild(button);
    bubble = document.createElement('div');
    bubble.className = 'bubble';
    bubble.hidden = true;
    shadow.appendChild(bubble);
    document.documentElement.appendChild(host);
  }

  function place(item, rect, width, height) {
    const x = Math.max(8, Math.min(rect.right + 8, window.innerWidth - width - 8));
    const below = rect.bottom + 8;
    const y = below + height <= window.innerHeight - 8 ? below : Math.max(8, rect.top - height - 8);
    item.style.left = `${x}px`;
    item.style.top = `${y}px`;
  }

  function close() {
    requestId += 1;
    if (button) button.hidden = true;
    if (bubble) bubble.hidden = true;
    openedAt = null;
  }

  function showButton(found) {
    ensureHost();
    selectedText = found.text;
    selectionRect = found.rect;
    bubble.hidden = true;
    place(button, found.rect, 30, 30);
    button.hidden = false;
    renderer().then(render => {
      button.title = render.L('翻译选中文字', 'Translate selection');
      button.setAttribute('aria-label', button.title);
    });
  }

  async function renderer() {
    if (!ui) {
      ui = Promise.all([
        import(chrome.runtime.getURL('lib/render.js')),
        import(chrome.runtime.getURL('lib/i18n.js'))
      ]).then(async ([render, language]) => { await language.loadLanguage(); return { ...render, L: language.L }; });
    }
    return ui;
  }

  async function openBubble(text, rect) {
    if (!text?.trim()) return;
    ensureHost();
    button.hidden = true;
    bubble.replaceChildren();
    bubble.hidden = false;
    const anchor = rect || { top: window.innerHeight / 2, bottom: window.innerHeight / 2, right: window.innerWidth / 2 };
    place(bubble, anchor, 380, 260);
    openedAt = { x: window.scrollX, y: window.scrollY };
    const id = ++requestId;
    const content = document.createElement('div');
    content.className = 'bubble-content';
    bubble.appendChild(content);
    try {
      const render = await renderer();
      if (id !== requestId) return;
      const progress = document.createElement('div');
      progress.className = 'progress';
      progress.textContent = render.L('查询中…', 'Looking up…');
      content.appendChild(progress);
      const reply = await chrome.runtime.sendMessage({ type: 'lookup', text: text.trim() });
      if (id !== requestId) return;
      if (!reply?.ok) throw new Error(reply?.error || render.L('查询失败', 'Lookup failed'));
      content.replaceChildren();
      const result = document.createElement('div');
      content.appendChild(result);
      const drawResult = async () => {
        const saved = await chrome.storage.local.get('favourites');
        if (id !== requestId) return;
        const favourites = saved.favourites || [];
        render.renderResult(result, reply.result, {
          compact: true,
          favourite: favourites.includes(reply.result.text),
          onFavourite: async word => {
            const latest = (await chrome.storage.local.get('favourites')).favourites || [];
            const next = latest.includes(word) ? latest.filter(item => item !== word) : [word, ...latest];
            await chrome.storage.local.set({ favourites: next });
            drawResult();
          }
        });
      };
      await drawResult();
      if (reply.result.kind === 'word') {
        const definitions = await chrome.runtime.sendMessage({ type: 'meanings', text: text.trim() });
        if (id !== requestId) return;
        const meaningBox = document.createElement('div');
        content.appendChild(meaningBox);
        if (definitions?.ok) render.renderMeanings(meaningBox, definitions.result);
        else render.renderError(meaningBox, definitions?.error || render.L('英英释义暂不可用', 'English definitions unavailable'));
      }
      place(bubble, anchor, bubble.offsetWidth, bubble.offsetHeight);
    } catch (error) {
      if (id !== requestId) return;
      content.replaceChildren();
      const render = await renderer().catch(() => null);
      if (render) render.renderError(content, error.message);
      else content.textContent = error.message;
    }
  }

  document.addEventListener('mouseup', async event => {
    if (event.composedPath().includes(host)) return;
    const found = selection();
    if (!found) { if (button) button.hidden = true; return; }
    const settings = await chrome.storage.local.get(['selectButton', 'selectDisabledSites']);
    if (settings.selectButton === false || (settings.selectDisabledSites || []).includes(location.hostname)) {
      if (button) button.hidden = true;
      return;
    }
    showButton(found);
  });
  document.addEventListener('mousedown', event => {
    if (event.composedPath().includes(host)) return;
    close();
  });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') close(); });
  window.addEventListener('scroll', () => {
    if (openedAt && (Math.abs(window.scrollX - openedAt.x) > 80 || Math.abs(window.scrollY - openedAt.y) > 80)) close();
    else if (button && !button.hidden) button.hidden = true;
  }, { passive: true, capture: true });
  chrome.runtime.onMessage.addListener(message => {
    if (message.type === 'translatePage') {
      const page = translatePage();
      const runId = pageRunId;
      page.catch(error => { if (pageActive && runId === pageRunId) showPagePill(error.message, true); });
      return;
    }
    if (message.type !== 'showBubble') return;
    const found = selection();
    const text = message.text || found?.text;
    if (text) openBubble(text, found?.rect);
  });
})();
