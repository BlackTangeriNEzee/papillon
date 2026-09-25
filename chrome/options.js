import { L, loadLanguage, watchLanguage } from './lib/i18n.js';
import { getAll, get, set } from './lib/storage.js';

const state = { providers: [], sourceOrder: [], sourceEnabled: {}, uiLanguage: 'system', selectButton: true, selectDisabledSites: [], favourites: [] };
const byId = id => document.getElementById(id);

function node(tag, className, text) {
  const item = document.createElement(tag);
  if (className) item.className = className;
  if (text !== undefined) item.textContent = String(text);
  return item;
}

function button(text, className, action) {
  const item = node('button', className, text);
  item.type = 'button';
  item.addEventListener('click', action);
  return item;
}

function secureText(value, key) {
  if (!key) return String(value);
  const visible = Math.min(4, key.length - 1);
  const masked = `${'•'.repeat(key.length - visible)}${key.slice(key.length - visible)}`;
  return String(value).split(key).join(masked);
}

function sourceIds() {
  return [...state.providers.map(provider => provider.id), 'google', 'mymemory'];
}

function normalizeSources() {
  const ids = sourceIds();
  state.sourceOrder = [...state.sourceOrder.filter(id => ids.includes(id)), ...ids.filter(id => !state.sourceOrder.includes(id))];
  state.sourceEnabled = Object.fromEntries(Object.entries(state.sourceEnabled).filter(([id]) => ids.includes(id)));
}

async function saveSources() {
  await set({ sourceOrder: state.sourceOrder, sourceEnabled: state.sourceEnabled });
}

function sourceName(id) {
  if (id === 'google') return 'Google';
  if (id === 'mymemory') return 'MyMemory';
  return state.providers.find(provider => provider.id === id)?.name || L('未命名', 'Unnamed');
}

function renderSources() {
  normalizeSources();
  const parent = byId('sources');
  parent.replaceChildren();
  const first = state.sourceOrder.find(id => state.sourceEnabled[id] !== false);
  state.sourceOrder.forEach((id, index) => {
    const row = node('div', 'source-row');
    row.appendChild(node('span', 'name', sourceName(id)));
    if (id === first) row.appendChild(node('span', 'tag', L('默认', 'Default')));
    const up = button('↑', 'icon-button', async () => { [state.sourceOrder[index - 1], state.sourceOrder[index]] = [id, state.sourceOrder[index - 1]]; await saveSources(); renderSources(); });
    up.disabled = index === 0;
    up.setAttribute('aria-label', `${L('上移', 'Move up')} ${sourceName(id)}`);
    const down = button('↓', 'icon-button', async () => { [state.sourceOrder[index + 1], state.sourceOrder[index]] = [id, state.sourceOrder[index + 1]]; await saveSources(); renderSources(); });
    down.disabled = index === state.sourceOrder.length - 1;
    down.setAttribute('aria-label', `${L('下移', 'Move down')} ${sourceName(id)}`);
    row.append(up, down);
    const toggle = node('input');
    toggle.type = 'checkbox';
    toggle.setAttribute('role', 'switch');
    toggle.setAttribute('aria-label', sourceName(id));
    toggle.checked = state.sourceEnabled[id] !== false;
    toggle.addEventListener('change', async () => { state.sourceEnabled[id] = toggle.checked; await saveSources(); renderSources(); });
    row.appendChild(toggle);
    parent.appendChild(row);
  });
}

function field(parent, provider, key, label, type = 'text') {
  const row = node('div', 'provider-field');
  const caption = node('label', '', label);
  const input = node('input');
  input.type = type;
  input.value = provider[key] || '';
  input.id = `${key}-${provider.id}`;
  caption.htmlFor = input.id;
  input.addEventListener('input', () => {
    provider[key] = input.value;
    set({ providers: state.providers });
    if (key === 'name') { parent.querySelector('h3').textContent = input.value || L('未命名', 'Unnamed'); renderSources(); }
  });
  row.append(caption, input);
  parent.appendChild(row);
}

async function testProvider(provider, status, test) {
  status.className = 'note';
  status.textContent = L('测试中…', 'Testing…');
  test.disabled = true;
  try {
    const reply = await chrome.runtime.sendMessage({ type: 'testProvider', provider: { ...provider } });
    if (!reply?.ok) throw new Error(reply?.error || L('测试失败', 'Test failed'));
    status.textContent = secureText(`${L('测试成功：', 'Test passed: ')}${reply.result}`, provider.key);
  } catch (error) {
    status.className = 'note error';
    status.textContent = secureText(`${L('测试失败：', 'Test failed: ')}${error.message}`, provider.key);
  } finally {
    test.disabled = false;
  }
}

function renderProviders() {
  const parent = byId('providers');
  parent.replaceChildren();
  state.providers.forEach(provider => {
    const card = node('div', 'provider-card');
    const head = node('div', 'provider-head');
    head.appendChild(node('h3', 'serif', provider.name || L('未命名', 'Unnamed')));
    const test = button(L('测试', 'Test'), 'pill secondary small', () => testProvider(provider, status, test));
    const remove = button(L('删除', 'Delete'), 'pill secondary small', async () => {
      state.providers = state.providers.filter(item => item.id !== provider.id);
      normalizeSources();
      await set({ providers: state.providers, sourceOrder: state.sourceOrder, sourceEnabled: state.sourceEnabled });
      renderProviders(); renderSources();
    });
    head.append(test, remove);
    card.appendChild(head);
    field(card, provider, 'name', L('名称', 'Name'));
    field(card, provider, 'base', L('API 地址', 'Base URL'));
    field(card, provider, 'key', L('密钥', 'Key'), 'password');
    field(card, provider, 'model', L('模型', 'Model'));
    const formatRow = node('div', 'provider-field');
    const caption = node('label', '', L('格式', 'Format'));
    const select = node('select');
    select.id = `format-${provider.id}`;
    caption.htmlFor = select.id;
    for (const [value, label] of [['openai', L('OpenAI 兼容', 'OpenAI compatible')], ['anthropic', 'Anthropic'], ['gemini', 'Gemini']]) {
      const option = node('option', '', label);
      option.value = value;
      select.appendChild(option);
    }
    select.value = provider.format || 'openai';
    select.addEventListener('change', () => { provider.format = select.value; set({ providers: state.providers }); });
    formatRow.append(caption, select);
    card.appendChild(formatRow);
    const status = node('div', 'note');
    status.setAttribute('role', 'status');
    card.appendChild(status);
    parent.appendChild(card);
  });
}

async function addProvider(preset = {}) {
  state.providers.push({ id: crypto.randomUUID(), name: preset.name || '', base: preset.base || '', key: '', model: preset.model || '', format: 'openai' });
  normalizeSources();
  await set({ providers: state.providers, sourceOrder: state.sourceOrder });
  renderProviders(); renderSources();
}

function renderLanguage() {
  const parent = byId('language');
  parent.replaceChildren();
  for (const [value, label] of [['zh', '中文'], ['en', 'English'], ['system', L('跟随系统', 'System')]]) {
    const item = button(label, state.uiLanguage === value ? 'selected' : '', async () => {
      state.uiLanguage = value;
      await set({ uiLanguage: value });
      renderLanguage();
    });
    item.setAttribute('aria-pressed', String(state.uiLanguage === value));
    parent.appendChild(item);
  }
}

function renderSites() {
  const parent = byId('disabled-sites');
  parent.replaceChildren();
  state.selectDisabledSites.forEach(site => {
    const row = node('div', 'site-row');
    row.appendChild(node('span', 'name', site));
    const remove = button(L('移除', 'Remove'), '', async () => {
      state.selectDisabledSites = state.selectDisabledSites.filter(item => item !== site);
      await set({ selectDisabledSites: state.selectDisabledSites });
      renderSites();
    });
    row.appendChild(remove);
    parent.appendChild(row);
  });
  if (!state.selectDisabledSites.length) parent.appendChild(node('p', 'note', L('尚无排除的网站', 'No excluded sites')));
}

function renderFavourites() {
  const parent = byId('favourites');
  parent.replaceChildren();
  state.favourites.forEach(word => {
    const row = node('div', 'favourite-row');
    row.appendChild(node('span', 'name', word));
    row.appendChild(button(L('移除', 'Remove'), '', async () => {
      state.favourites = state.favourites.filter(item => item !== word);
      await set({ favourites: state.favourites });
      renderFavourites();
    }));
    parent.appendChild(row);
  });
  if (!state.favourites.length) parent.appendChild(node('p', 'note', L('尚无收藏', 'No favourites yet')));
}

function labels() {
  document.documentElement.lang = L('zh', 'en');
  document.title = L('蝶笺', 'Papillon');
  byId('title').textContent = L('设置', 'Settings');
  byId('subtitle').textContent = L('蝶笺', 'Papillon');
  byId('language-title').textContent = L('界面语言', 'Interface language');
  byId('language-note').textContent = L('中文输入翻译成英文，其他输入翻译成简体中文。', 'Chinese input is translated to English, anything else to Simplified Chinese.');
  byId('sources-title').textContent = L('翻译顺序', 'Translation order');
  byId('sources-note').textContent = L('单词和短语总是先查有道词典；其他内容按下面的顺序尝试。', 'Words and phrases try Youdao first; other text follows this order.');
  byId('reset-order').textContent = L('恢复默认顺序', 'Reset order');
  byId('providers-title').textContent = L('API 服务', 'API providers');
  byId('add-api').textContent = L('添加 API', 'Add API');
  byId('selection-title').textContent = L('划词翻译', 'Select to translate');
  byId('select-label').textContent = L('显示划词按钮', 'Show selection button');
  byId('disabled-title').textContent = L('排除的网站', 'Excluded sites');
  byId('site-input').placeholder = L('example.com', 'example.com');
  byId('add-site-button').textContent = L('添加', 'Add');
  byId('favourites-title').textContent = L('收藏', 'Favourites');
  renderLanguage(); renderSources(); renderProviders(); renderSites(); renderFavourites();
}

await loadLanguage();
Object.assign(state, await getAll());
if (!Array.isArray(state.providers)) state.providers = [];
if (!Array.isArray(state.sourceOrder)) state.sourceOrder = [];
if (!state.sourceEnabled || typeof state.sourceEnabled !== 'object') state.sourceEnabled = {};
if (!Array.isArray(state.selectDisabledSites)) state.selectDisabledSites = [];
if (!Array.isArray(state.favourites)) state.favourites = [];
labels();
watchLanguage(async () => { state.uiLanguage = await get('uiLanguage', 'system'); labels(); });
byId('select-button').checked = state.selectButton !== false;
byId('select-button').addEventListener('change', event => { state.selectButton = event.target.checked; set({ selectButton: state.selectButton }); });
byId('reset-order').addEventListener('click', async () => { state.sourceOrder = sourceIds(); state.sourceEnabled = {}; await saveSources(); renderSources(); });
byId('add-api').addEventListener('click', () => addProvider());
byId('add-deepseek').addEventListener('click', () => addProvider({ name: 'DeepSeek', base: 'https://api.deepseek.com', model: 'deepseek-chat' }));
byId('add-openai').addEventListener('click', () => addProvider({ name: 'OpenAI', base: 'https://api.openai.com', model: 'gpt-6-luna' }));
byId('add-site').addEventListener('submit', async event => {
  event.preventDefault();
  const input = byId('site-input');
  const site = input.value.trim().toLowerCase();
  if (!/^(?=.{1,253}$)[a-z0-9-]+(?:\.[a-z0-9-]+)*$/.test(site)) { input.setCustomValidity(L('请输入主机名，例如 example.com', 'Enter a hostname such as example.com')); input.reportValidity(); return; }
  input.setCustomValidity('');
  if (!state.selectDisabledSites.includes(site)) {
    state.selectDisabledSites.push(site);
    await set({ selectDisabledSites: state.selectDisabledSites });
  }
  input.value = '';
  renderSites();
});
byId('site-input').addEventListener('input', event => event.target.setCustomValidity(''));
