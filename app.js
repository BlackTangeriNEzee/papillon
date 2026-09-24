const $ = (id) => document.getElementById(id);
const CJK = /[\u3400-\u9fff\uf900-\ufaff]/;
const SETTING_FIELDS = { base: 'api-base', key: 'api-key', model: 'api-model' };
let searchId = 0;
let ocrId = 0;

const load = (key, empty = []) => JSON.parse(localStorage.getItem(key) || JSON.stringify(empty));
const store = (key, value) => localStorage.setItem(key, JSON.stringify(value));
const norm = (text) => text.toLowerCase().replace(/[\s.,!?;:。，！？；：]+/g, '');

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function button(text, onClick, className) {
  const node = el('button', className, text);
  node.type = 'button';
  node.onclick = onClick;
  return node;
}

function setStatus(node, text, isError = false) {
  node.textContent = text;
  node.classList.toggle('error', isError);
}

function apiSettings() {
  const settings = load('settings', {});
  return settings.base && settings.key && settings.model ? settings : null;
}

async function request(url, options) {
  try {
    return await fetch(url, options);
  } catch (error) {
    throw new Error(`网络错误 Network error (${new URL(url).host}): ${error.message}. 可能是网络或跨域限制 Possibly offline or blocked by CORS.`);
  }
}

async function myMemory(text, toEnglish) {
  const langpair = toEnglish ? 'zh-CN|en' : 'en|zh-CN';
  const res = await request(`https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=${encodeURIComponent(langpair)}`);
  if (!res.ok) throw new Error(`翻译失败 Translation failed: HTTP ${res.status}`);
  const data = await res.json();
  if (Number(data.responseStatus) !== 200) throw new Error(`翻译失败 Translation failed: ${data.responseStatus} ${data.responseDetails}`);
  return data;
}

async function callApi(settings, system, text) {
  const res = await request(`${settings.base.replace(/\/+$/, '')}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${settings.key}` },
    body: JSON.stringify({ model: settings.model, messages: [{ role: 'system', content: system }, { role: 'user', content: text }] }),
  });
  const body = await res.text();
  let data = null;
  try { data = JSON.parse(body); } catch {}
  if (!res.ok) throw new Error(`API 错误 API error: HTTP ${res.status} ${data?.error?.message || body.slice(0, 300)}`);
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== 'string') throw new Error(`API 返回格式不对 Unexpected API response: ${body.slice(0, 300)}`);
  return content.trim();
}

async function translateSearch(text, isWord) {
  const toEnglish = CJK.test(text);
  const settings = apiSettings();
  if (!settings) {
    const data = await myMemory(text, toEnglish);
    const sameSegment = (data.matches || []).filter((m) => norm(m.segment || '') === norm(text));
    const seen = new Set([norm(text)]);
    const candidates = [];
    for (const candidate of [data.responseData.translatedText, ...sameSegment.map((m) => m.translation)]) {
      const key = norm(candidate || '');
      if (!key || seen.has(key) || candidate.includes('\uFFFD')) continue;
      seen.add(key);
      candidates.push(candidate.trim());
    }
    return { route: '免费 Free', candidates: candidates.slice(0, 5), senses: [] };
  }
  const language = toEnglish ? 'English' : 'Simplified Chinese';
  const sensesRule = isWord ? ', "senses": [up to 5 main senses of this English word, each a short one-line explanation in Simplified Chinese]' : '';
  const content = await callApi(settings, `Translate the user's text into ${language}. Reply with JSON only, no code fences, in this shape: {"translations": [up to 5 distinct candidate translations, best first]${sensesRule}}`, text);
  let parsed;
  try { parsed = JSON.parse(content.replace(/^```(?:json)?\s*|\s*```$/g, '')); } catch {}
  if (!Array.isArray(parsed?.translations)) throw new Error(`API 返回格式不对 Unexpected API reply: ${content.slice(0, 300)}`);
  return { route: 'API', candidates: parsed.translations.map(String).slice(0, 5), senses: (parsed.senses || []).map(String).slice(0, 5) };
}

async function translateText(text) {
  const toEnglish = CJK.test(text);
  const settings = apiSettings();
  if (settings) return { route: 'API', text: await callApi(settings, `Translate the user's text into ${toEnglish ? 'English' : 'Simplified Chinese'}. Reply with the translation only.`, text) };
  const parts = text.match(/[\s\S]{1,450}(?:(?=\s)|$)|[\s\S]{1,450}/g).map((part) => part.trim()).filter(Boolean);
  const results = [];
  for (const part of parts) results.push((await myMemory(part, toEnglish)).responseData.translatedText);
  return { route: '免费 Free', text: results.join('\n') };
}

async function lookup(word) {
  const res = await request(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function search(raw) {
  const text = raw.trim();
  $('query').value = text;
  $('result').replaceChildren();
  if (!text) return setStatus($('status'), '请输入单词或短语 Please enter a word or phrase', true);
  const id = ++searchId;
  addHistory(text);
  setStatus($('status'), '查询中 Searching…');
  const isWord = /^[a-z][a-z'-]*$/i.test(text);
  const dictionary = isWord ? lookup(text).then((value) => ({ value }), (error) => ({ error })) : null;
  const [translation] = await Promise.allSettled([translateSearch(text, isWord)]);
  if (id !== searchId) return;
  setStatus($('status'), '');
  const node = renderResult(text, translation, isWord);
  $('result').replaceChildren(node);
  if (!dictionary) return;
  const pending = el('p', 'note', '词典加载中 Loading dictionary…');
  node.append(pending);
  const { value, error } = await dictionary;
  if (id !== searchId) return;
  if (error) return pending.replaceWith(el('p', 'note', `词典暂不可用 Dictionary entry unavailable (${error.message})`));
  if (!value) return pending.replaceWith(el('p', 'error', '词典中未找到该词 Word not found in dictionary'));
  node.querySelector('.result-head').after(...renderPhonetic(value));
  pending.replaceWith(...renderMeanings(value));
}

function renderResult(text, translation, isWord) {
  const node = el('div');
  const head = el('div', 'result-head');
  head.append(el('span', 'word', text));
  if (translation.status === 'fulfilled') head.append(el('span', 'route', translation.value.route));
  head.append(starButton(text));
  node.append(head);
  if (translation.status === 'rejected') node.append(el('p', 'error', translation.reason.message));
  else if (!translation.value.candidates.length) node.append(el('p', 'error', '未找到翻译 No translation found'));
  else {
    const list = el('ol', 'candidates');
    list.append(...translation.value.candidates.map((candidate) => el('li', '', candidate)));
    node.append(list);
  }
  if (!isWord) return node;
  node.append(el('h3', '', '释义 Senses'));
  const senses = translation.status === 'fulfilled' ? translation.value.senses : [];
  if (senses.length) {
    const list = el('ol', 'senses');
    list.append(...senses.map((sense) => el('li', '', sense)));
    node.append(list);
  }
  return node;
}

function renderPhonetic(entries) {
  const phonetics = entries.flatMap((entry) => entry.phonetics || []);
  const ipa = entries.find((entry) => entry.phonetic)?.phonetic || phonetics.find((p) => p.text)?.text;
  const audio = phonetics.find((p) => p.audio)?.audio;
  if (!ipa && !audio) return [];
  const line = el('div', 'phonetic', ipa || '');
  if (audio) line.append(button('发音 Play', () => new Audio(audio).play().catch((error) => setStatus($('status'), `播放失败 Audio failed: ${error.message}`, true))));
  return [line];
}

function renderMeanings(entries) {
  const groups = new Map();
  for (const meaning of entries.flatMap((entry) => entry.meanings || [])) {
    const group = groups.get(meaning.partOfSpeech) || { definitions: [], synonyms: [] };
    group.definitions.push(...meaning.definitions);
    group.synonyms.push(...(meaning.synonyms || []), ...meaning.definitions.flatMap((d) => d.synonyms || []));
    groups.set(meaning.partOfSpeech, group);
  }
  const nodes = [];
  for (const [partOfSpeech, group] of groups) {
    const list = el('ol');
    for (const definition of group.definitions.slice(0, 5)) {
      const item = el('li', '', definition.definition);
      if (definition.example) item.append(el('div', 'example', `例 e.g. ${definition.example}`));
      list.append(item);
    }
    nodes.push(el('p', 'pos', partOfSpeech), list);
    const synonyms = [...new Set(group.synonyms)].slice(0, 5);
    if (synonyms.length) nodes.push(el('p', 'synonyms', `近义词 Synonyms: ${synonyms.join(', ')}`));
  }
  return nodes;
}

function starButton(text) {
  const node = button('', () => {
    const favourites = load('favourites');
    store('favourites', favourites.includes(text) ? favourites.filter((f) => f !== text) : [text, ...favourites]);
    paint();
    renderLists();
  }, 'star');
  const paint = () => {
    const on = load('favourites').includes(text);
    node.textContent = on ? '★' : '☆';
    node.setAttribute('aria-pressed', String(on));
    node.setAttribute('aria-label', on ? '取消收藏 Remove favourite' : '收藏 Add favourite');
  };
  paint();
  return node;
}

function addHistory(text) {
  store('history', [text, ...load('history').filter((item) => item !== text)].slice(0, 20));
  renderLists();
}

function renderLists() {
  for (const key of ['history', 'favourites']) {
    const items = load(key);
    $(key).replaceChildren(...items.map((text) => {
      const item = el('li');
      item.append(button(text, () => search(text)));
      return item;
    }));
    if (!items.length) $(key).append(el('li', 'note', '暂无 None yet'));
  }
}

function togglePanel(buttonId, open) {
  const toggle = $(buttonId);
  const panel = $(toggle.getAttribute('aria-controls'));
  const show = open ?? panel.hidden;
  panel.hidden = !show;
  toggle.setAttribute('aria-expanded', String(show));
}

function currentStatus() {
  return $('ocr-panel').hidden ? $('status') : $('ocr-status');
}

async function runOcr(file) {
  const id = ++ocrId;
  togglePanel('toggle-ocr', true);
  const status = $('ocr-status');
  if (!file.type.startsWith('image/')) return setStatus(status, '请选择图片文件 Please choose an image file', true);
  if ($('preview').src) URL.revokeObjectURL($('preview').src);
  $('preview').src = URL.createObjectURL(file);
  $('preview').hidden = false;
  $('ocr-text').value = '';
  $('ocr-result').replaceChildren();
  setStatus(status, '准备识别 Starting OCR… 0%');
  let worker;
  try {
    if (typeof Tesseract === 'undefined') throw new Error('OCR 库未加载 The OCR library failed to load');
    worker = await Tesseract.createWorker(['eng', 'chi_sim'], 1, {
      logger: (m) => id === ocrId && setStatus(status, `识别中 OCR: ${m.status} ${Math.round((m.progress || 0) * 100)}%`),
    });
    const { data } = await worker.recognize(file);
    if (id !== ocrId) return;
    const text = data.text.replace(/([\u3400-\u9fff])[ \t]+(?=[\u3400-\u9fff])/g, '$1').trim();
    $('ocr-text').value = text;
    setStatus(status, text ? '识别完成 OCR done 100%' : '没有识别出文字 No text found in the image', !text);
  } catch (error) {
    if (id === ocrId) setStatus(status, `识别失败 OCR failed: ${error.message || error}`, true);
  } finally {
    if (worker) worker.terminate();
  }
}

async function translateOcr() {
  const text = $('ocr-text').value.trim();
  const out = $('ocr-result');
  if (!text) return out.replaceChildren(el('p', 'error', '没有可翻译的文字 Nothing to translate'));
  out.replaceChildren(el('p', 'note', '翻译中 Translating…'));
  try {
    const result = await translateText(text);
    out.replaceChildren(el('span', 'route', result.route), el('p', 'translation', result.text));
  } catch (error) {
    out.replaceChildren(el('p', 'error', error.message));
  }
}

function fillSettings() {
  const settings = load('settings', {});
  for (const [key, id] of Object.entries(SETTING_FIELDS)) $(id).value = settings[key] || '';
}

$('search-form').onsubmit = (event) => {
  event.preventDefault();
  search($('query').value);
};
$('clear-history').onclick = () => {
  store('history', []);
  renderLists();
};
$('toggle-ocr').onclick = () => togglePanel('toggle-ocr');
$('toggle-lists').onclick = () => togglePanel('toggle-lists');
$('ocr-translate').onclick = translateOcr;
$('file').onchange = (event) => {
  const file = event.target.files[0];
  event.target.value = '';
  if (file) runOcr(file);
};

$('open-settings').onclick = () => {
  fillSettings();
  setStatus($('settings-status'), '');
  $('settings').showModal();
};
$('save-settings').onclick = () => {
  const settings = Object.fromEntries(Object.entries(SETTING_FIELDS).map(([key, id]) => [key, $(id).value.trim()]));
  store('settings', settings);
  setStatus($('settings-status'), apiSettings() ? '已保存，将使用 API Saved, the API will be used' : '已保存，但未填全，将使用免费翻译 Saved, but not all fields are filled, so the free route is used');
};
$('clear-settings').onclick = () => {
  localStorage.removeItem('settings');
  fillSettings();
  setStatus($('settings-status'), '已清除，将使用免费翻译 Cleared, the free route is used');
};

document.addEventListener('paste', (event) => {
  const file = [...event.clipboardData.items].find((item) => item.kind === 'file' && item.type.startsWith('image/'))?.getAsFile();
  if (file) {
    event.preventDefault();
    runOcr(file);
  } else if (!event.target.closest('input, textarea')) {
    setStatus(currentStatus(), '剪贴板里没有图片 No image in the clipboard', true);
  }
});
document.addEventListener('dragover', (event) => {
  event.preventDefault();
  $('drop-zone').classList.add('over');
});
document.addEventListener('dragleave', () => $('drop-zone').classList.remove('over'));
document.addEventListener('drop', (event) => {
  event.preventDefault();
  $('drop-zone').classList.remove('over');
  const file = [...event.dataTransfer.files].find((f) => f.type.startsWith('image/'));
  if (file) runOcr(file);
  else setStatus(currentStatus(), '请拖入图片文件 Please drop an image file', true);
});

let popupText = '';
let pointer = null;

function selectedText() {
  const active = document.activeElement;
  if (active === $('ocr-text')) return active.value.slice(active.selectionStart, active.selectionEnd);
  if (active?.matches('input, textarea') || $('settings').open) return '';
  const selection = getSelection();
  if (!selection.rangeCount || $('popup').contains(selection.anchorNode)) return '';
  return selection.toString();
}

function hidePopup() {
  $('popup').hidden = true;
  popupText = '';
}

function showPopup() {
  const text = selectedText().trim();
  if (!text || text.length > 200 || (text === popupText && !$('popup').hidden)) return;
  popupText = text;
  const popup = $('popup');
  $('popup-text').textContent = text;
  $('popup-result').replaceChildren();
  popup.hidden = false;
  const selection = getSelection();
  const rect = selection.rangeCount ? selection.getRangeAt(0).getBoundingClientRect() : null;
  const anchor = rect?.width ? { x: rect.left, y: rect.bottom } : pointer || { x: 16, y: 16 };
  const maxLeft = document.documentElement.clientWidth - popup.offsetWidth - 16;
  popup.style.left = `${Math.max(16, Math.min(anchor.x, maxLeft)) + scrollX}px`;
  popup.style.top = `${anchor.y + scrollY + 8}px`;
}

async function translatePopup() {
  const text = popupText;
  const out = $('popup-result');
  out.replaceChildren(el('p', 'note', '翻译中 Translating…'));
  try {
    const result = await translateSearch(text, false);
    if (text !== popupText) return;
    if (!result.candidates.length) return out.replaceChildren(el('p', 'error', '未找到翻译 No translation found'));
    const list = el('ol');
    list.append(...result.candidates.map((candidate) => el('li', '', candidate)));
    out.replaceChildren(list, el('p', 'route', result.route));
  } catch (error) {
    if (text === popupText) out.replaceChildren(el('p', 'error', error.message));
  }
}

$('popup-translate').onclick = translatePopup;
$('popup-search').onclick = () => {
  const text = popupText;
  hidePopup();
  scrollTo(0, 0);
  search(text);
};

let selectTimer;
const queuePopup = () => {
  clearTimeout(selectTimer);
  selectTimer = setTimeout(showPopup, 250);
};
document.addEventListener('selectionchange', queuePopup);
document.addEventListener('pointerup', (event) => {
  pointer = { x: event.clientX, y: event.clientY };
  queuePopup();
});
document.addEventListener('pointerdown', (event) => {
  if (!$('popup').contains(event.target)) hidePopup();
});
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') hidePopup();
});

renderLists();
