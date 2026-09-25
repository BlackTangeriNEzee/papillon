import { L } from './i18n.js';

export function encode(text) {
  return encodeURIComponent(text).replace(/[!'()*]/g, (char) => '%' + char.charCodeAt(0).toString(16).toUpperCase());
}

export async function request(url, init = {}) {
  try {
    const response = await fetch(url, init);
    return { status: response.status, body: await response.text() };
  } catch (error) {
    throw new Error(`${L('网络错误', 'Network error')} (${new URL(url).host}): ${error.message}`);
  }
}

export function parseJson(body) {
  try {
    return JSON.parse(body);
  } catch {
    return undefined;
  }
}

export function ok(status) {
  return status >= 200 && status < 300;
}

export function withTimeout(seconds, work) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${L('超时', 'timed out')} (${Math.trunc(seconds)} s)`)), seconds * 1000);
  });
  const job = Promise.resolve().then(work);
  job.catch(() => {});
  return Promise.race([job, timeout]).finally(() => clearTimeout(timer));
}
