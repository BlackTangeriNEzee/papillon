import { L } from './i18n.js';
import { encode, ok, parseJson, request, withTimeout } from './net.js';
import { get, getAll } from './storage.js';
import { chunks, isCJK, kind, norm, usesDictionary, withLowercase } from './text.js';
import { lookupWiktionary } from './wiktionary.js';
import { lookupYoudao } from './youdao.js';

const browser = { headers: { 'User-Agent': 'Mozilla/5.0' } };

function messageOf(error) {
  return error instanceof Error && error.message ? error.message : String(error);
}

function trimProvider(provider) {
  return {
    ...provider,
    name: (provider?.name ?? '').trim(),
    base: (provider?.base ?? '').trim(),
    key: (provider?.key ?? '').trim(),
    model: (provider?.model ?? '').trim(),
    format: provider?.format || 'openai',
  };
}

function usable(provider) {
  const clean = trimProvider(provider);
  return Boolean(clean.key && clean.base && clean.model);
}

function titleOf(provider) {
  return provider.name || L('未命名', 'Unnamed');
}

function routeOf(provider) {
  return `${titleOf(provider)} · ${provider.model}`;
}

function sourceName(id, providers) {
  if (id === 'google') return 'Google';
  if (id === 'mymemory') return 'MyMemory';
  const provider = providers.find((item) => item.id === id);
  return provider ? titleOf(trimProvider(provider)) : id;
}

function enabledSources(settings) {
  const enabled = settings.sourceEnabled || {};
  return settings.sourceOrder.filter((id) => enabled[id] !== false);
}

function translator(toEnglish) {
  const language = toEnglish ? 'English' : 'Simplified Chinese';
  return `You are a professional translator. Translate the user's text into natural, idiomatic ${language} that a native speaker would write, keeping the meaning, tone and register. Never translate word for word and never add explanations.`;
}

function linesOf(text) {
  return text.split(/\r\n|[\n\r\u000B\u000C\u0085\u2028\u2029]/);
}

function googlePiece(item) {
  if (typeof item === 'string') return item;
  if (Array.isArray(item) && typeof item[0] === 'string') return item[0];
  return '';
}

export async function googleText(text, toEnglish) {
  const stored = await get('googleBase', 'https://translate.googleapis.com');
  const base = `${stored || 'https://translate.googleapis.com'}`.replace(/\/+$/, '');
  const pair = toEnglish ? 'sl=zh-CN&tl=en' : 'sl=en&tl=zh-CN';
  const lines = [];
  for (const line of linesOf(text)) {
    const parts = [];
    for (const part of chunks(line, 1500)) {
      const url = `${base}/translate_a/t?client=dict-chrome-ex&${pair}&q=${encode(part)}`;
      const { status, body } = await request(url, browser);
      if (!ok(status)) throw new Error(`HTTP ${status}`);
      const reply = parseJson(body);
      if (!Array.isArray(reply)) throw new Error(L('返回格式不对', 'unexpected reply'));
      parts.push(reply.map(googlePiece).join(''));
    }
    lines.push(parts.join(toEnglish ? ' ' : ''));
  }
  const result = lines.join('\n').trim();
  if (!result) throw new Error(L('没有返回译文', 'no translation returned'));
  return result;
}

function translatedText(reply) {
  const value = reply?.responseData?.translatedText;
  return typeof value === 'string' ? value : '';
}

export async function myMemory(text, toEnglish) {
  const pair = toEnglish ? 'zh-CN|en' : 'en|zh-CN';
  const url = `https://api.mymemory.translated.net/get?q=${encode(text)}&langpair=${encode(pair)}`;
  const { status, body } = await request(url, browser);
  const failed = L('翻译失败：', 'Translation failed: ');
  if (!ok(status)) throw new Error(failed + `HTTP ${status}`);
  const reply = parseJson(body);
  if (!reply || typeof reply !== 'object' || Array.isArray(reply)) throw new Error(failed + body.slice(0, 300));
  const code = `${reply.responseStatus ?? 'none'}`;
  if (code !== '200') throw new Error(failed + `${code} ${reply.responseDetails ?? ''}`);
  return reply;
}

export async function freeText(text, toEnglish) {
  const lines = [];
  for (const line of linesOf(text)) {
    const parts = [];
    for (const part of chunks(line)) parts.push(translatedText(await myMemory(part, toEnglish)));
    lines.push(parts.join(toEnglish ? ' ' : ''));
  }
  return lines.join('\n').trim();
}

export async function myMemoryCandidates(text, toEnglish) {
  const reply = await myMemory(text, toEnglish);
  const matches = (Array.isArray(reply.matches) ? reply.matches : []).filter((item) => norm(item?.segment ?? '') === norm(text));
  const seen = new Set([norm(text)]);
  const candidates = [];
  const found = [translatedText(reply), ...matches.map((item) => (typeof item?.translation === 'string' ? item.translation : ''))];
  for (const candidate of found) {
    const key = norm(candidate);
    if (!key || seen.has(key) || candidate.includes('\uFFFD')) continue;
    seen.add(key);
    candidates.push(candidate.trim());
    if (candidates.length === 5) break;
  }
  return { route: '', candidates, senses: [], fallback: null };
}

async function freeSource(source, text) {
  const english = isCJK(text);
  return withTimeout(8, () => (source === 'google' ? googleText(text, english) : freeText(text, english)));
}

function endpoint(api) {
  let base = api.base;
  while (base.endsWith('/')) base = base.slice(0, -1);
  if (api.format === 'anthropic') return `${base}/messages`;
  if (api.format === 'gemini') return `${base}/models/${api.model}:generateContent?key=${encode(api.key)}`;
  return `${base}/chat/completions`;
}

function apiRequest(api, system, text) {
  let url;
  try {
    url = new URL(endpoint(api));
  } catch {
    throw new Error(L('API 地址无效：', 'Invalid API base URL: ') + api.base);
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error(L('API 地址无效：', 'Invalid API base URL: ') + api.base);
  }
  const headers = { 'Content-Type': 'application/json' };
  let body;
  if (api.format === 'anthropic') {
    headers['x-api-key'] = api.key;
    headers['anthropic-version'] = '2023-06-01';
    body = { model: api.model, max_tokens: 2048, system, messages: [{ role: 'user', content: text }] };
  } else if (api.format === 'gemini') {
    body = { systemInstruction: { parts: [{ text: system }] }, contents: [{ parts: [{ text }] }] };
  } else {
    headers.Authorization = `Bearer ${api.key}`;
    body = { model: api.model, temperature: 0.3, messages: [{ role: 'system', content: system }, { role: 'user', content: text }] };
  }
  return { url, init: { method: 'POST', headers, body: JSON.stringify(body) } };
}

function providerContent(format, reply) {
  if (format === 'anthropic') {
    const text = reply?.content?.[0]?.text;
    return typeof text === 'string' ? text : undefined;
  }
  if (format === 'gemini') {
    const text = reply?.candidates?.[0]?.content?.parts?.[0]?.text;
    return typeof text === 'string' ? text : undefined;
  }
  const text = reply?.choices?.[0]?.message?.content;
  return typeof text === 'string' ? text : undefined;
}

export async function callApi(provider, system, text) {
  const api = trimProvider(provider);
  const { url, init } = apiRequest(api, system, text);
  const { status, body } = await request(url, init);
  const reply = parseJson(body);
  if (!ok(status)) {
    const error = reply && typeof reply === 'object' ? reply.error : undefined;
    const detail = (error && typeof error === 'object' && typeof error.message === 'string' && error.message)
      || (typeof error === 'string' && error)
      || body.slice(0, 300);
    throw new Error(`HTTP ${status} ${detail}`);
  }
  const content = providerContent(api.format, reply);
  if (typeof content !== 'string') throw new Error(L('API 返回格式不对：', 'Unexpected API response: ') + body.slice(0, 300));
  return content.trim();
}

function senseObject(sense) {
  if (sense && typeof sense === 'object') return { label: `${sense.label ?? ''}`, text: `${sense.text ?? ''}` };
  return { label: '', text: `${sense ?? ''}` };
}

function stripFence(content) {
  return content.replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
}

function translationFromApi(content) {
  const reply = parseJson(stripFence(content));
  const translations = reply && typeof reply === 'object' && !Array.isArray(reply) ? reply.translations : undefined;
  if (!Array.isArray(translations)) throw new Error(L('API 返回格式不对：', 'Unexpected API reply: ') + content.slice(0, 300));
  const senses = Array.isArray(reply.senses) ? reply.senses : [];
  return {
    route: '',
    candidates: translations.slice(0, 5).map((item) => `${item ?? ''}`),
    senses: senses.slice(0, 5).map(senseObject),
    fallback: null,
  };
}

async function chain(apiWork, freeWork) {
  const settings = await getAll();
  const sources = enabledSources(settings);
  if (!sources.length) {
    throw new Error(L(
      '没有启用的翻译来源，请在“设置 > API > 翻译顺序”中打开至少一个',
      'No translation source is enabled; turn one on in Settings > API > Translation order',
    ));
  }
  const notes = [];
  for (const source of sources) {
    const name = sourceName(source, settings.providers);
    try {
      if (source !== 'google' && source !== 'mymemory') {
        const provider = settings.providers.find((item) => item.id === source);
        if (!provider || !usable(provider)) {
          notes.push(name + L('：未填密钥，已跳过', ': no key, skipped'));
          continue;
        }
        const clean = trimProvider(provider);
        return { value: await apiWork(clean), route: routeOf(clean), note: notes.length ? notes.join('; ') : null };
      }
      return { value: await freeWork(source), route: name, note: notes.length ? notes.join('; ') : null };
    } catch (error) {
      notes.push(`${name}: ${messageOf(error)}`);
    }
  }
  throw new Error(notes.join('; '));
}

export async function search(text, isWord) {
  const english = isCJK(text);
  const sensesRule = isWord
    ? ', "senses": [up to 5 main senses of this English word, each a short, natural one-line explanation in Simplified Chinese]'
    : '';
  const system = `${translator(english)} Reply with JSON only, no code fences, in this shape: {"translations": [up to 5 distinct candidate translations, ordered from the most common everyday rendering to rarer ones]${sensesRule}}`;
  const answered = await chain(
    async (api) => translationFromApi(await callApi(api, system, text)),
    (source) => (source === 'mymemory'
      ? withTimeout(8, () => myMemoryCandidates(text, english))
      : freeSource(source, text).then((value) => ({ route: '', candidates: [value], senses: [], fallback: null }))),
  );
  return { ...answered.value, route: answered.route, fallback: answered.note };
}

export async function translateParagraph(text) {
  const english = isCJK(text);
  const system = `${translator(english)} Keep the paragraph breaks. Reply with the translation only.`;
  const answered = await chain(
    (api) => callApi(api, system, text),
    (source) => freeSource(source, text),
  );
  return { route: answered.route, text: answered.value, fallback: answered.note };
}

const numberedPrompt = 'You receive numbered lines. Translate each line and reply with the same number of lines in the same order, each line prefixed with its number and a tab, nothing else.';

function oneLine(text) {
  return linesOf(text).join(' ');
}

function parseNumbered(content, count) {
  const found = new Map();
  for (const line of linesOf(content)) {
    const match = /^\s*(\d+)\t(.*)$/.exec(line);
    if (!match) continue;
    found.set(Number(match[1]), match[2].trim());
  }
  const texts = [];
  for (let index = 1; index <= count; index += 1) {
    const value = found.get(index);
    if (!value) break;
    texts.push(value);
  }
  if (texts.length !== count || found.size !== count) {
    throw new Error(L(
      `译文条数不符：需要 ${count} 条，得到 ${found.size} 条`,
      `Translation count mismatch: expected ${count}, got ${found.size}`,
    ));
  }
  return texts;
}

async function translateBatch(api, texts, toEnglish) {
  const body = texts.map((text, index) => `${index + 1}\t${oneLine(text)}`).join('\n');
  return parseNumbered(await callApi(api, `${translator(toEnglish)} ${numberedPrompt}`, body), texts.length);
}

async function translateWithProvider(api, texts) {
  const results = [];
  let start = 0;
  while (start < texts.length) {
    const toEnglish = isCJK(texts[start]);
    let end = start + 1;
    while (end < texts.length && end - start < 20 && isCJK(texts[end]) === toEnglish) end += 1;
    results.push(...await translateBatch(api, texts.slice(start, end), toEnglish));
    start = end;
  }
  return results;
}

async function pool(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  async function run() {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await worker(items[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, () => run()));
  return results;
}

async function googleBatch(texts, toEnglish) {
  const stored = await get('googleBase', 'https://translate.googleapis.com');
  const base = `${stored || 'https://translate.googleapis.com'}`.replace(/\/+$/, '');
  const pair = toEnglish ? 'sl=zh-CN&tl=en' : 'sl=en&tl=zh-CN';
  const url = `${base}/translate_a/t?client=dict-chrome-ex&${pair}`;
  const payload = texts.map((text) => `q=${encode(oneLine(text))}`).join('&');
  const { status, body } = await request(url, {
    method: 'POST',
    headers: { ...browser.headers, 'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8' },
    body: payload,
  });
  if (!ok(status)) throw new Error(`HTTP ${status}`);
  const reply = parseJson(body);
  if (!Array.isArray(reply)) throw new Error(L('返回格式不对', 'unexpected reply'));
  if (reply.length !== texts.length) {
    throw new Error(L(
      `译文条数不符：需要 ${texts.length} 条，得到 ${reply.length} 条`,
      `Translation count mismatch: expected ${texts.length}, got ${reply.length}`,
    ));
  }
  const translated = reply.map((item) => googlePiece(item).trim());
  if (translated.some((item) => !item)) throw new Error(L('没有返回译文', 'no translation returned'));
  return translated;
}

async function translateGoogleFree(texts) {
  const batches = [];
  let start = 0;
  while (start < texts.length) {
    const toEnglish = isCJK(texts[start]);
    let end = start + 1;
    while (end < texts.length && end - start < 20 && isCJK(texts[end]) === toEnglish) end += 1;
    batches.push({ texts: texts.slice(start, end), toEnglish });
    start = end;
  }
  const parts = await pool(batches, 3, (batch) => googleBatch(batch.texts, batch.toEnglish));
  const results = [];
  for (const part of parts) results.push(...part);
  return results;
}

function translateFree(source, texts) {
  if (source === 'google') return translateGoogleFree(texts);
  return pool(texts, 4, (text) => freeSource(source, text));
}

export async function translateTexts(texts) {
  if (!Array.isArray(texts) || texts.some((item) => typeof item !== 'string')) {
    throw new Error(L('texts 必须是字符串数组', 'texts must be an array of strings'));
  }
  if (texts.length > 500) {
    throw new Error(L('一次最多翻译 500 条', 'At most 500 texts at once'));
  }
  if (!texts.length) return { route: '', texts: [], note: null };
  const answered = await chain(
    (api) => translateWithProvider(api, texts),
    (source) => translateFree(source, texts),
  );
  return { route: answered.route, texts: answered.value, note: answered.note };
}

export async function translateGoogle(text) {
  return googleText(text, isCJK(text));
}

export async function translateMyMemory(text) {
  return withTimeout(8, () => myMemoryCandidates(text, isCJK(text)));
}

export async function translateProvider(provider, text, isWord = false) {
  const clean = trimProvider(provider);
  if (!usable(clean)) throw new Error(L('请先填写地址、密钥和模型', 'Fill in the base URL, key and model first'));
  const english = isCJK(text);
  const sensesRule = isWord
    ? ', "senses": [up to 5 main senses of this English word, each a short, natural one-line explanation in Simplified Chinese]'
    : '';
  const system = `${translator(english)} Reply with JSON only, no code fences, in this shape: {"translations": [up to 5 distinct candidate translations, ordered from the most common everyday rendering to rarer ones]${sensesRule}}`;
  const translation = translationFromApi(await callApi(clean, system, text));
  return { ...translation, route: routeOf(clean) };
}

function briefOf(entry, translation) {
  if (entry) {
    const sense = entry.senses[0];
    return [sense?.label, sense?.text].filter(Boolean).join(' ');
  }
  return translation?.candidates?.[0] ?? '';
}

async function dictionaryEntry(text) {
  try {
    return { entry: await withLowercase(text, lookupYoudao), error: null };
  } catch (error) {
    return { entry: null, error };
  }
}

export async function lookup(raw) {
  const text = `${raw ?? ''}`.trim();
  if (!text) throw new Error(L('请输入要翻译的内容', 'Please enter a word, phrase or paragraph'));
  const textKind = kind(text);
  const found = usesDictionary(text) ? await dictionaryEntry(text) : { entry: null, error: null };
  let translation = null;
  if (!found.entry) {
    try {
      translation = textKind === 'paragraph'
        ? await paragraphResult(text)
        : await search(text, textKind === 'word');
    } catch (error) {
      if (!found.error) throw error;
      throw new Error(`${messageOf(found.error)}; ${messageOf(error)}`);
    }
    if (found.error) {
      const note = messageOf(found.error);
      translation = { ...translation, fallback: translation.fallback ? `${note}; ${translation.fallback}` : note };
    }
  }
  return { text, kind: textKind, entry: found.entry, translation, brief: briefOf(found.entry, translation) };
}

async function paragraphResult(text) {
  const translated = await translateParagraph(text);
  return { route: translated.route, candidates: [translated.text], senses: [], fallback: translated.fallback };
}

export async function meanings(raw) {
  const text = `${raw ?? ''}`.trim();
  if (!text) return null;
  return withLowercase(text, lookupWiktionary);
}

export async function testProvider(provider) {
  const clean = trimProvider(provider);
  if (!usable(clean)) throw new Error(L('请先填写地址、密钥和模型', 'Fill in the base URL, key and model first'));
  return callApi(clean, "Translate the user's text into Simplified Chinese. Reply with the translation only.", 'hello');
}
