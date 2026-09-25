let setting = 'system';

function systemIsChinese() {
  return (globalThis.navigator?.language ?? '').toLowerCase().startsWith('zh');
}

export function isChinese() {
  if (setting === 'zh') return true;
  if (setting === 'en') return false;
  return systemIsChinese();
}

export function L(zh, en) {
  return isChinese() ? zh : en;
}

export function setLanguage(value) {
  setting = value === 'zh' || value === 'en' ? value : 'system';
}

export async function loadLanguage() {
  const stored = await chrome.storage.local.get('uiLanguage');
  setLanguage(stored.uiLanguage);
  return setting;
}

export function watchLanguage(onChange) {
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !changes.uiLanguage) return;
    setLanguage(changes.uiLanguage.newValue);
    onChange?.();
  });
}
