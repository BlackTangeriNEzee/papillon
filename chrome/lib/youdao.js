import { L } from './i18n.js';
import { encode, ok, parseJson, request } from './net.js';
import { isCJK } from './text.js';

const browser = { headers: { 'User-Agent': 'Mozilla/5.0' } };

export function youdaoURL(text) {
  const dict = isCJK(text) ? 'ce' : 'ec';
  const dicts = JSON.stringify({ count: 99, dicts: [[dict, 'web_trans']] });
  return `https://dict.youdao.com/jsonapi?q=${encode(text)}&dicts=${encode(dicts)}`;
}

export function audioURL(word, american) {
  return `https://dict.youdao.com/dictvoice?audio=${encode(word)}&type=${american ? 2 : 1}`;
}

function phone(word, key) {
  const value = word?.[key];
  return typeof value === 'string' && value ? value : null;
}

function linesOf(word) {
  const lines = [];
  for (const item of word?.trs ?? []) {
    const line = item?.tr?.[0]?.l?.i;
    if (line != null) lines.push(line);
  }
  return lines;
}

function englishSense(line) {
  if (!Array.isArray(line) || typeof line[0] !== 'string' || !line[0]) return null;
  const text = line[0];
  const space = text.indexOf(' ');
  if (space > 0 && text.slice(0, space).endsWith('.')) {
    return { label: text.slice(0, space), text: text.slice(space + 1) };
  }
  return { label: '', text };
}

function chineseSense(line) {
  const parts = (Array.isArray(line) ? line : []).map((part) => {
    if (typeof part === 'string') return part;
    return typeof part?.['#text'] === 'string' ? part['#text'] : '';
  });
  const text = parts.join('').replace(/^[ \t]+|[ \t]+$/g, '');
  return text ? { label: '', text } : null;
}

function webOf(json) {
  const items = json?.web_trans?.['web-translation']?.[0]?.trans ?? [];
  const values = [];
  for (const item of items) {
    if (typeof item?.value === 'string') values.push(item.value);
    if (values.length === 5) break;
  }
  return values;
}

export function parseYoudao(json, text) {
  if (!json || typeof json !== 'object' || Array.isArray(json)) return null;
  const dict = isCJK(text) ? 'ce' : 'ec';
  const section = json[dict];
  if (!section || typeof section !== 'object') return null;
  const word = Array.isArray(section.word) ? section.word[0] : undefined;
  if (!word || typeof word !== 'object') throw new Error(L('返回格式不对', 'unexpected reply'));
  const senses = linesOf(word).map(isCJK(text) ? chineseSense : englishSense).filter(Boolean);
  if (!senses.length) return null;
  return {
    uk: phone(word, 'ukphone'),
    us: phone(word, 'usphone'),
    pinyin: phone(word, 'phone'),
    senses,
    web: webOf(json),
    audio: { uk: audioURL(text, false), us: audioURL(text, true) },
  };
}

export async function lookupYoudao(text) {
  const { status, body } = await request(youdaoURL(text), browser);
  if (!ok(status)) throw new Error(`HTTP ${status}`);
  const reply = parseJson(body);
  if (!reply || typeof reply !== 'object' || Array.isArray(reply)) throw new Error(L('返回格式不对', 'unexpected reply'));
  return parseYoudao(reply, text);
}
