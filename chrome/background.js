import { L, loadLanguage, setLanguage, watchLanguage } from './lib/i18n.js';
import { withTimeout } from './lib/net.js';
import { getAll, set } from './lib/storage.js';
import { lookup, meanings, testProvider, translateTexts } from './lib/translate.js';

const MENU_ID = 'translate-selection';
const PAGE_MENU_ID = 'translate-page';

function menuTitle() {
  return L('用蝶笺翻译', 'Translate with Papillon');
}

function pageMenuTitle() {
  return L('翻译整个网页', 'Translate this page');
}

function chromeCall(method, ...args) {
  return new Promise((resolve) => {
    method(...args, () => {
      const error = chrome.runtime.lastError;
      if (error) console.error(error.message);
      resolve();
    });
  });
}

async function installMenu() {
  try {
    await loadLanguage();
  } catch {
    setLanguage('system');
  }
  await chromeCall(chrome.contextMenus.removeAll.bind(chrome.contextMenus));
  await chromeCall(chrome.contextMenus.create.bind(chrome.contextMenus), {
    id: MENU_ID,
    title: menuTitle(),
    contexts: ['selection'],
  });
  await chromeCall(chrome.contextMenus.create.bind(chrome.contextMenus), {
    id: PAGE_MENU_ID,
    title: pageMenuTitle(),
    contexts: ['page', 'selection', 'link', 'image'],
  });
}

let menuQueue = Promise.resolve();

function refreshMenu() {
  menuQueue = menuQueue.then(installMenu).catch((error) => console.error(messageOf(error)));
}

chrome.runtime.onInstalled.addListener(() => {
  refreshMenu();
});

chrome.runtime.onStartup.addListener(() => {
  refreshMenu();
});

watchLanguage(() => {
  refreshMenu();
});

async function showBubble(tabId, text) {
  if (tabId == null) return;
  const message = text === undefined ? { type: 'showBubble' } : { type: 'showBubble', text };
  try {
    await chrome.tabs.sendMessage(tabId, message);
  } catch (error) {
    console.error(messageOf(error));
  }
}

async function translatePage(tabId) {
  if (tabId == null) return;
  try {
    await chrome.tabs.sendMessage(tabId, { type: 'translatePage' });
  } catch (error) {
    console.error(messageOf(error));
  }
}

function messageOf(error) {
  return error instanceof Error && error.message ? error.message : String(error);
}

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === MENU_ID) {
    showBubble(tab?.id, info.selectionText ?? '');
    return;
  }
  if (info.menuItemId === PAGE_MENU_ID) translatePage(tab?.id);
});

chrome.commands.onCommand.addListener((command) => {
  if (command !== 'translate-selection') return;
  chrome.tabs.query({ active: true, currentWindow: true }).then(
    ([tab]) => showBubble(tab?.id),
    (error) => console.error(messageOf(error)),
  );
});

async function noteHistory(text, brief) {
  const all = await getAll();
  const history = [text, ...all.history.filter((item) => item !== text)].slice(0, 200);
  const keep = new Set([...history, ...all.favourites]);
  const briefs = {};
  for (const [key, value] of Object.entries(all.briefs)) {
    if (keep.has(key) && typeof value === 'string') briefs[key] = value;
  }
  if (brief) briefs[text] = [...brief].slice(0, 80).join('');
  await set({ history, briefs });
}

function toBase64(bytes) {
  let binary = '';
  for (let index = 0; index < bytes.length; index += 1024) {
    binary += String.fromCharCode(...bytes.subarray(index, index + 1024));
  }
  return btoa(binary);
}

async function audioDataUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    parsed = null;
  }
  if (!parsed || (parsed.protocol !== 'https:' && parsed.protocol !== 'http:')) {
    throw new Error(`${L('播放失败：', 'Audio failed: ')}${L('没有音频地址', 'missing audio URL')}`);
  }
  return withTimeout(15, async () => {
    let response;
    try {
      response = await fetch(parsed);
    } catch (error) {
      throw new Error(`${L('播放失败：', 'Audio failed: ')}${messageOf(error)}`);
    }
    if (!response.ok) throw new Error(`${L('播放失败：', 'Audio failed: ')}HTTP ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    const mime = (response.headers.get('content-type') || 'audio/mpeg').split(';')[0].trim() || 'audio/mpeg';
    return `data:${mime};base64,${toBase64(bytes)}`;
  });
}

function dispatch(message) {
  switch (message?.type) {
    case 'lookup':
      return lookup(message.text).then(async (result) => {
        await noteHistory(result.text, result.brief);
        return { result };
      });
    case 'meanings':
      return meanings(message.text).then((result) => ({ result }));
    case 'testProvider':
      return testProvider(message.provider).then((result) => ({ result }));
    case 'translateTexts':
      return translateTexts(message.texts).then((result) => ({ result }));
    case 'audio':
      return audioDataUrl(message.url).then((dataUrl) => ({ dataUrl }));
    default:
      return null;
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const task = dispatch(message);
  if (!task) return;
  task.then(
    (payload) => sendResponse({ ok: true, ...payload }),
    (error) => sendResponse({ ok: false, error: messageOf(error) }),
  );
  return true;
});
