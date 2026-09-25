import { L } from './i18n.js';

function element(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (value !== undefined && value !== null) node.textContent = String(value);
  return node;
}

function add(parent, child) {
  parent.appendChild(child);
  return child;
}

function note(parent, value, error = false) {
  return add(parent, element('div', `note${error ? ' error' : ''}`, value));
}

async function playAudio(url, target) {
  try {
    const reply = await chrome.runtime.sendMessage({ type: 'audio', url });
    if (!reply?.ok || !reply.dataUrl) throw new Error(reply?.error || L('发音不可用', 'Audio unavailable'));
    const audio = new Audio(reply.dataUrl);
    await audio.play();
  } catch (error) {
    note(target, error.message, true);
  }
}

function phonetic(parent, region, ipa, url) {
  if (!ipa) return;
  const row = add(parent, element('span', 'phonetic'));
  add(row, element('span', 'region', region));
  add(row, element('span', '', `[${ipa}]`));
  if (url) {
    const button = add(row, element('button', 'icon-button', '▶'));
    button.type = 'button';
    button.title = L('发音', 'Play audio');
    button.setAttribute('aria-label', `${region} ${L('发音', 'Play audio')}`);
    button.addEventListener('click', () => playAudio(url, parent));
  }
}

function sense(parent, item) {
  const row = add(parent, element('div', 'sense-row'));
  if (item.label) add(row, element('span', 'sense-label', item.label));
  add(row, element('span', 'sense-text', item.text));
}

function numbered(parent, items) {
  items.forEach((item, index) => {
    const row = add(parent, element('div', 'numbered'));
    add(row, element('span', 'numbered-index', `${index + 1}.`));
    add(row, element('span', 'candidate-text', item));
  });
}

export function renderResult(container, result, options = {}) {
  container.replaceChildren();
  const card = add(container, element('section', `card result-card${options.compact ? ' compact' : ''}`));
  const head = add(card, element('div', 'result-head'));
  if (!(options.compact && result.kind === 'paragraph')) add(head, element('h2', 'result-title serif', result.text));
  if (!options.compact && result.entry) {
    const phones = add(head, element('div', 'phonetics'));
    phonetic(phones, L('英', 'UK'), result.entry.uk, result.entry.audio?.uk);
    phonetic(phones, L('美', 'US'), result.entry.us, result.entry.audio?.us);
    if (result.entry.pinyin) add(phones, element('span', 'note', `[${result.entry.pinyin}]`));
  }
  add(head, element('span', 'spacer'));
  if (result.entry) add(head, element('span', 'tag', L('有道', 'Youdao')));
  if (options.onFavourite) {
    const star = add(head, element('button', `icon-button${options.favourite ? ' active' : ''}`, options.favourite ? '★' : '☆'));
    star.type = 'button';
    star.title = options.favourite ? L('取消收藏', 'Remove favourite') : L('收藏', 'Add favourite');
    star.setAttribute('aria-label', star.title);
    star.addEventListener('click', () => options.onFavourite(result.text));
  }
  if (options.compact && result.entry) {
    const phones = add(card, element('div', 'phonetics'));
    phonetic(phones, L('英', 'UK'), result.entry.uk, result.entry.audio?.uk);
    phonetic(phones, L('美', 'US'), result.entry.us, result.entry.audio?.us);
    if (result.entry.pinyin) add(phones, element('span', 'note', `[${result.entry.pinyin}]`));
  }
  if (result.translation) {
    const translation = result.translation;
    if (translation.route) add(card, element('span', 'tag', translation.route));
    if (translation.fallback) note(card, translation.fallback);
    if (translation.candidates?.length) {
      if (result.kind === 'paragraph') add(card, element('div', 'candidate-text paragraph', translation.candidates[0]));
      else numbered(card, translation.candidates);
    } else note(card, L('未找到翻译', 'No translation found'), true);
    if (translation.senses?.length) {
      add(card, element('h3', 'section-title serif', L('释义', 'Senses')));
      translation.senses.forEach(item => sense(card, item));
    }
  }
  if (result.entry) {
    result.entry.senses?.forEach(item => sense(card, item));
    if (result.entry.web?.length) {
      const row = add(card, element('div', 'sense-row'));
      add(row, element('span', 'web-label', L('网络', 'Web')));
      const values = add(row, element('div', 'web-values'));
      result.entry.web.forEach(value => add(values, element('span', 'web-value', value)));
    }
  }
  return card;
}

export function renderMeanings(container, meanings) {
  container.replaceChildren();
  const details = add(container, element('details', 'card definitions'));
  add(details, element('summary', 'section-title serif', L('英英释义', 'English definitions')));
  const body = add(details, element('div', 'definitions-body'));
  if (!meanings?.length) {
    note(body, L('没有英英释义', 'No English definitions found'));
    return details;
  }
  const abbreviations = { noun: 'n.', verb: 'v.', adjective: 'adj.', adverb: 'adv.', interjection: 'interj.', preposition: 'prep.', conjunction: 'conj.', pronoun: 'pron.' };
  meanings.forEach(meaning => {
    const row = add(body, element('div', 'sense-row'));
    add(row, element('span', 'sense-label', abbreviations[meaning.partOfSpeech?.toLowerCase()] || meaning.partOfSpeech));
    const definitions = add(row, element('div'));
    meaning.definitions?.forEach((definition, index) => {
      add(definitions, element('div', '', `${index + 1}. ${definition.text}`));
      if (definition.example) add(definitions, element('div', 'definition-example', L('例：', 'e.g. ') + definition.example));
    });
  });
  return details;
}

export function renderError(container, message) {
  container.replaceChildren();
  note(container, message, true);
}
