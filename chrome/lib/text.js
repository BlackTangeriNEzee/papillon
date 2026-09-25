const segmenter = new Intl.Segmenter();
const newline = /[\n\r\u000B\u000C\u0085\u2028\u2029]/;
const punctuation = /[\s.,!?;:\u3002\uff0c\uff01\uff1f\uff1b\uff1a]+/g;
const sentenceEnd = /[.!?\u3002\uff01\uff1f]\s*\S/;
const entityNames = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

export function length(text) {
  let count = 0;
  for (const _ of segmenter.segment(text)) count += 1;
  return count;
}

export function words(text) {
  return text.split(/\s+/).filter(Boolean);
}

export function hasNewline(text) {
  return newline.test(text);
}

export function isCJK(text) {
  return /[\u3400-\u9fff\uf900-\ufaff]/.test(text);
}

export function isWord(text) {
  return /^[a-z][a-z'-]*$/i.test(text);
}

export function isSentence(text) {
  return isCJK(text) ? length(text) >= 8 : words(text).length >= 3;
}

export function kind(text) {
  if (isWord(text)) return 'word';
  const short = length(text) < 60 && words(text).length <= 6;
  const oneSentence = !sentenceEnd.test(text);
  if (!(short && oneSentence && !hasNewline(text))) return 'paragraph';
  return isSentence(text) ? 'sentence' : 'phrase';
}

export function usesDictionary(text) {
  const value = kind(text);
  return value === 'word' || value === 'phrase';
}

export function norm(text) {
  return text.toLowerCase().replace(punctuation, '');
}

function entity(match, name) {
  if (name in entityNames) return entityNames[name];
  const hex = /^#[xX]/.test(name);
  const number = hex ? parseInt(name.slice(2), 16) : name.startsWith('#') ? parseInt(name.slice(1), 10) : NaN;
  if (!Number.isInteger(number) || number > 0x10ffff || (number >= 0xd800 && number <= 0xdfff)) return match;
  return String.fromCodePoint(number);
}

export function plain(html) {
  return html
    .replace(/<(style|script)\b[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/<[^>]*>/g, '')
    .replace(/&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);/g, entity)
    .replace(/\s+/g, ' ')
    .trim();
}

function lastSpace(head) {
  for (let index = head.length - 1; index > 0; index -= 1) {
    if (/\s/.test(head[index])) return index;
  }
  return head.length;
}

export function chunks(text, size = 450) {
  const parts = [];
  let rest = Array.from(text);
  while (rest.length > size) {
    const cut = lastSpace(rest.slice(0, size));
    parts.push(rest.slice(0, cut).join(''));
    rest = rest.slice(cut);
  }
  parts.push(rest.join(''));
  return parts.map((part) => part.trim()).filter(Boolean);
}

export async function withLowercase(text, lookup) {
  const found = await lookup(text);
  if (found) return found;
  if (text === text.toLowerCase()) return null;
  return lookup(text.toLowerCase());
}
