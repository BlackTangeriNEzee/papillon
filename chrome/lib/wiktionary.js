import { L } from './i18n.js';
import { encode, ok, parseJson, request } from './net.js';
import { plain } from './text.js';

const browser = { headers: { 'User-Agent': 'Mozilla/5.0' } };

export function wiktionaryURL(word) {
  return `https://en.wiktionary.org/api/rest_v1/page/definition/${encode(word)}`;
}

function definitionsOf(entry) {
  const definitions = [];
  for (const item of entry?.definitions ?? []) {
    const text = plain(typeof item?.definition === 'string' ? item.definition : '');
    if (!text) continue;
    const example = plain(typeof item?.examples?.[0] === 'string' ? item.examples[0] : '');
    definitions.push({ text, example });
  }
  return definitions;
}

function takeFive(lists) {
  const definitions = [];
  let index = 0;
  while (definitions.length < 5 && lists.some((list) => index < list.length)) {
    for (const list of lists) {
      if (index < list.length && definitions.length < 5) definitions.push(list[index]);
    }
    index += 1;
  }
  return definitions;
}

export function parseWiktionary(json) {
  if (!json || typeof json !== 'object') return null;
  const order = [];
  const groups = new Map();
  for (const entry of json.en ?? []) {
    const partOfSpeech = typeof entry?.partOfSpeech === 'string' ? entry.partOfSpeech : '';
    const definitions = definitionsOf(entry);
    if (!definitions.length) continue;
    if (!groups.has(partOfSpeech)) {
      order.push(partOfSpeech);
      groups.set(partOfSpeech, []);
    }
    groups.get(partOfSpeech).push(definitions);
  }
  if (!order.length) return null;
  return order.map((partOfSpeech) => ({
    partOfSpeech,
    definitions: takeFive(groups.get(partOfSpeech)),
  }));
}

export async function lookupWiktionary(word) {
  const { status, body } = await request(wiktionaryURL(word), browser);
  if (status === 404) return null;
  if (!ok(status)) throw new Error(`HTTP ${status}`);
  const reply = parseJson(body);
  if (!reply || typeof reply !== 'object' || Array.isArray(reply)) throw new Error(L('返回格式不对', 'unexpected reply'));
  return parseWiktionary(reply);
}
