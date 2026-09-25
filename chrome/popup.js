import { L, loadLanguage, watchLanguage } from './lib/i18n.js';
import { get, set, onChange } from './lib/storage.js';
import { renderResult, renderMeanings, renderError } from './lib/render.js';

const query = document.getElementById('query');
const historyBox = document.getElementById('history');
const resultBox = document.getElementById('result');
const meaningsBox = document.getElementById('meanings');
const status = document.getElementById('status');
let history = [];
let briefs = {};
let favourites = [];
let current = null;
let meanings = null;
let requestId = 0;
let historyOpen = false;

function showStatus(text, error = false, loading = false) {
  status.replaceChildren();
  if (!text) return;
  const node = document.createElement('div');
  node.className = loading ? 'progress' : `note${error ? ' error' : ''}`;
  node.textContent = text;
  status.appendChild(node);
}

function renderCurrent() {
  if (!current) return;
  renderResult(resultBox, current, { favourite: favourites.includes(current.text), onFavourite: toggleFavourite });
  if (current.kind === 'word' && meanings !== undefined) renderMeanings(meaningsBox, meanings);
}

async function toggleFavourite(text) {
  favourites = favourites.includes(text) ? favourites.filter(item => item !== text) : [text, ...favourites];
  await set({ favourites });
  renderCurrent();
}

function matches() {
  const typed = query.value.trim().toLowerCase();
  const starts = history.filter(item => item.toLowerCase().startsWith(typed));
  const contains = history.filter(item => !item.toLowerCase().startsWith(typed) && item.toLowerCase().includes(typed));
  return [...starts, ...contains].slice(0, 10);
}

function renderHistory() {
  historyBox.replaceChildren();
  const items = matches();
  historyBox.hidden = !historyOpen || !items.length || document.activeElement !== query;
  if (historyBox.hidden) return;
  const list = document.createElement('div');
  list.className = 'history-list';
  historyBox.appendChild(list);
  items.forEach(item => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'history-row';
    const icon = document.createElement('span');
    icon.className = 'history-icon';
    icon.textContent = '◷';
    const name = document.createElement('span');
    name.className = 'history-query';
    name.textContent = item.replaceAll('\n', ' ');
    const brief = document.createElement('span');
    brief.className = 'history-brief';
    brief.textContent = briefs[item] || '';
    row.append(icon, name, brief);
    row.addEventListener('click', () => { query.value = item; search(); });
    list.appendChild(row);
  });
  const clear = document.createElement('button');
  clear.type = 'button';
  clear.className = 'history-clear';
  clear.textContent = L('清空', 'Clear');
  clear.addEventListener('click', async () => { history = []; await set({ history }); renderHistory(); });
  historyBox.appendChild(clear);
}

async function search() {
  const text = query.value.trim();
  historyOpen = false;
  historyBox.hidden = true;
  if (!text) { showStatus(L('请输入要翻译的内容', 'Please enter a word, phrase or paragraph'), true); return; }
  query.value = text;
  current = null;
  meanings = undefined;
  resultBox.replaceChildren();
  meaningsBox.replaceChildren();
  showStatus(L('查询中…', 'Looking up…'), false, true);
  const id = ++requestId;
  history = [text, ...history.filter(item => item !== text)].slice(0, 200);
  await set({ history });
  try {
    const reply = await chrome.runtime.sendMessage({ type: 'lookup', text });
    if (id !== requestId) return;
    if (!reply?.ok) throw new Error(reply?.error || L('查询失败', 'Lookup failed'));
    current = reply.result;
    showStatus('');
    renderCurrent();
    if (current.brief) {
      briefs = { ...briefs, [text]: current.brief.slice(0, 80) };
      await set({ briefs });
    }
    if (current.kind === 'word') {
      const definitions = await chrome.runtime.sendMessage({ type: 'meanings', text });
      if (id !== requestId) return;
      if (!definitions?.ok) throw new Error(definitions?.error || L('英英释义暂不可用', 'English definitions unavailable'));
      meanings = definitions.result;
      renderMeanings(meaningsBox, meanings);
    }
  } catch (error) {
    if (id !== requestId) return;
    if (current) showStatus(error.message, true);
    else renderError(resultBox, error.message);
  }
}

function labels() {
  document.documentElement.lang = L('zh', 'en');
  document.title = L('蝶笺', 'Papillon');
  document.getElementById('app-title').textContent = L('蝶笺', 'Papillon');
  document.getElementById('settings').textContent = '⚙';
  document.getElementById('settings').title = L('设置', 'Settings');
  document.getElementById('settings').setAttribute('aria-label', L('设置', 'Settings'));
  query.placeholder = L('输入单词、短语或段落，回车翻译', 'Type a word, phrase or paragraph. Enter translates');
  document.getElementById('submit').setAttribute('aria-label', L('翻译', 'Translate'));
  document.getElementById('translate-page').textContent = L('翻译当前网页', 'Translate this page');
  renderHistory();
  renderCurrent();
}

await loadLanguage();
[history, briefs, favourites] = await Promise.all([get('history', []), get('briefs', {}), get('favourites', [])]);
labels();
watchLanguage(labels);
onChange(changes => {
  if (changes.favourites) { favourites = changes.favourites.newValue || []; renderCurrent(); }
  if (changes.history) { history = changes.history.newValue || []; if (!historyBox.hidden) renderHistory(); }
  if (changes.briefs) { briefs = changes.briefs.newValue || {}; if (!historyBox.hidden) renderHistory(); }
});
query.addEventListener('focus', () => { historyOpen = true; renderHistory(); });
query.addEventListener('input', () => { historyOpen = true; renderHistory(); });
query.addEventListener('click', () => { historyOpen = true; renderHistory(); });
query.addEventListener('keydown', event => {
  if (event.key === 'Escape') { historyOpen = false; historyBox.hidden = true; return; }
  if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); search(); }
});
query.addEventListener('blur', () => { historyOpen = false; setTimeout(() => { if (!historyOpen) historyBox.hidden = true; }, 150); });
document.getElementById('submit').addEventListener('click', search);
document.getElementById('translate-page').addEventListener('click', async () => {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id) throw new Error('No active tab');
    await chrome.tabs.sendMessage(tab.id, { type: 'translatePage' });
    showStatus('');
  } catch {
    showStatus(L('这个页面不能翻译', 'This page cannot be translated'), true);
  }
});
document.getElementById('settings').addEventListener('click', event => { event.preventDefault(); chrome.runtime.openOptionsPage(); });
