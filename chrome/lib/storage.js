const PRESETS = [
  { name: 'DeepSeek', base: 'https://api.deepseek.com', model: 'deepseek-chat' },
  { name: 'OpenAI', base: 'https://api.openai.com', model: 'gpt-6-luna' },
];

const FREE = ['google', 'mymemory'];

function makePresets() {
  return PRESETS.map((preset) => ({
    id: crypto.randomUUID(),
    name: preset.name,
    base: preset.base,
    key: '',
    model: preset.model,
    format: 'openai',
  }));
}

function cleanProviders(value) {
  if (!Array.isArray(value)) return null;
  return value.filter((item) => item && typeof item === 'object').map((item) => ({
    id: typeof item.id === 'string' && item.id ? item.id : crypto.randomUUID(),
    name: typeof item.name === 'string' ? item.name : '',
    base: typeof item.base === 'string' ? item.base : '',
    key: typeof item.key === 'string' ? item.key : '',
    model: typeof item.model === 'string' ? item.model : '',
    format: item.format === 'anthropic' || item.format === 'gemini' ? item.format : 'openai',
  }));
}

function mergeOrder(saved, providers) {
  const valid = [...providers.map((provider) => provider.id), ...FREE];
  const known = new Set(valid);
  const order = [];
  const seed = Array.isArray(saved) ? saved : valid;
  for (const id of [...seed, ...valid]) {
    if (typeof id === 'string' && known.has(id) && !order.includes(id)) order.push(id);
  }
  return order;
}

function strings(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string') : [];
}

async function readAll() {
  const stored = await chrome.storage.local.get(null);
  const patch = {};
  let providers = cleanProviders(stored.providers);
  if (!providers) {
    providers = makePresets();
    patch.providers = providers;
  }
  const sourceOrder = mergeOrder(stored.sourceOrder, providers);
  if (!Array.isArray(stored.sourceOrder)) patch.sourceOrder = sourceOrder;
  if (Object.keys(patch).length) await chrome.storage.local.set(patch);
  const enabled = stored.sourceEnabled && typeof stored.sourceEnabled === 'object' && !Array.isArray(stored.sourceEnabled)
    ? stored.sourceEnabled
    : {};
  const googleBase = typeof stored.googleBase === 'string' ? stored.googleBase.trim() : '';
  return {
    providers,
    sourceOrder,
    sourceEnabled: enabled,
    history: strings(stored.history).slice(0, 200),
    briefs: stored.briefs && typeof stored.briefs === 'object' && !Array.isArray(stored.briefs) ? stored.briefs : {},
    favourites: strings(stored.favourites),
    uiLanguage: stored.uiLanguage === 'zh' || stored.uiLanguage === 'en' ? stored.uiLanguage : 'system',
    selectButton: typeof stored.selectButton === 'boolean' ? stored.selectButton : true,
    selectDisabledSites: strings(stored.selectDisabledSites),
    googleBase: googleBase || 'https://translate.googleapis.com',
  };
}

let loading;

export function getAll() {
  if (!loading) loading = readAll().finally(() => { loading = undefined; });
  return loading;
}

export async function get(key, fallback) {
  const all = await getAll();
  return Object.prototype.hasOwnProperty.call(all, key) ? all[key] : fallback;
}

export function set(patch) {
  return chrome.storage.local.set(patch);
}

export function onChange(callback) {
  const listener = (changes, area) => {
    if (area === 'local') callback(changes);
  };
  chrome.storage.onChanged.addListener(listener);
  return () => chrome.storage.onChanged.removeListener(listener);
}
