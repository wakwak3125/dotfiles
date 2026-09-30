// 作業役が書いた引用が、出典に本当にあるかを文字列で照合する。
//
// モデルに確かめさせると、もっともらしい誤りを通す弱点をそのまま持ち込むので、機械的な照合で受け止める。
// 照合の誤りは「捏造を通す」より「正しい引用を無いとする」ほうが起きやすい（vagus research の試走で、
// 出典にある引用 32 件を無いと判定した）。そのため本文を取り出せないときは not_found ではなく unverifiable にする。

import { spawnSync } from 'node:child_process';
import { readFile, stat } from 'node:fs/promises';
import { isAbsolute } from 'node:path';

const FETCH_TIMEOUT_MS = 20_000;
// 公式ドキュメントでも SDK のリファレンスは 500 万文字を超える（実測）
const MAX_BODY_BYTES = 20_000_000;
const FETCH_CONCURRENCY = 8;
// 短い引用はどの本文にも現れうるので、照合の意味をなさない。... でつないだ断片も 1 つずつ同じ扱いにする
const MIN_QUOTE_CHARS = 12;
const MIN_FRAGMENT_CHARS = 6;
// ... でつないだ断片が本文の離れた場所に散らばっていると、別々の文をつないだ捏造も通ってしまう
const MAX_FRAGMENT_GAP = 2_000;

export const STATUSES = ['verified', 'not_found', 'unverifiable'];

/** 主張 1 件の形を確かめる。形の崩れた主張は、その主張だけを照合できないものとして残す */
export function parseClaim(entry) {
  const record = typeof entry === 'object' && entry !== null ? entry : {};
  const text = (value) => (typeof value === 'string' ? value : '');
  const claim = { claim: text(record.claim), source: text(record.source), quote: text(record.quote) };
  const problems = [];
  if (claim.claim.trim() === '') problems.push('claim が空');
  if (claim.quote.trim() === '') problems.push('quote が空');
  if (!/^https?:\/\//.test(claim.source) && !isAbsolute(claim.source)) {
    problems.push('source は URL か絶対パスで書く');
  }
  const fragments = quoteFragments(claim.quote);
  if (claim.quote.trim() !== '' && (fragments.join('').length < MIN_QUOTE_CHARS || fragments.some((part) => part.length < MIN_FRAGMENT_CHARS))) {
    problems.push(`引用が短すぎて照合にならない（全体で ${MIN_QUOTE_CHARS} 文字、... の断片ごとに ${MIN_FRAGMENT_CHARS} 文字以上）`);
  }
  return { claim, problems };
}

export async function checkClaims(entries, fetchText = fetchSourceText) {
  const cache = new Map();
  const load = (source) => {
    let pending = cache.get(source);
    if (pending === undefined) {
      pending = (/^https?:\/\//.test(source) ? fetchText(source) : readLocalFile(source)).catch((error) => ({
        ok: false,
        detail: `取得できない: ${error instanceof Error ? error.message : String(error)}`,
      }));
      cache.set(source, pending);
    }
    return pending;
  };
  const results = new Array(entries.length);
  let next = 0;
  const lane = async () => {
    for (;;) {
      const index = next;
      next += 1;
      if (index >= entries.length) return;
      // 1 件の例外で全体の照合結果を失わないよう、主張ごとに閉じ込める
      try {
        results[index] = await checkOne(entries[index], load);
      } catch (error) {
        const { claim } = parseClaim(entries[index]);
        results[index] = {
          ...claim,
          status: 'unverifiable',
          detail: `照合の途中で失敗した: ${error instanceof Error ? error.message : String(error)}`,
        };
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(FETCH_CONCURRENCY, entries.length) }, lane));
  return results;
}

async function checkOne(entry, load) {
  const { claim, problems } = parseClaim(entry);
  if (problems.length > 0) {
    return { ...claim, status: 'unverifiable', detail: `主張の形が合わない: ${problems.join(' / ')}` };
  }
  const source = await load(claim.source);
  if (!source.ok) return { ...claim, status: 'unverifiable', detail: source.detail };
  if (containsQuote(source.text, claim.quote)) return { ...claim, status: 'verified' };
  return { ...claim, status: 'not_found', detail: '出典の本文に引用の文面が無い' };
}

function quoteFragments(quote) {
  return quote
    .split(/\.\.\.|…/)
    .map(normalize)
    .filter((part) => part !== '');
}

/** 空白・引用符・ダッシュの表記揺れと大文字小文字は無視し、... で省いた箇所は近くに順に並んでいればよい */
export function containsQuote(text, quote) {
  const haystack = normalize(text);
  const parts = quoteFragments(quote);
  if (parts.length === 0) return false;
  // 先頭の断片が複数の場所に現れうるので、どの出現から始めても残りが続けば一致とする
  let start = haystack.indexOf(parts[0]);
  while (start !== -1) {
    let from = start + parts[0].length;
    let matched = true;
    for (const part of parts.slice(1)) {
      const index = haystack.indexOf(part, from);
      if (index === -1 || index - from > MAX_FRAGMENT_GAP) {
        matched = false;
        break;
      }
      from = index + part.length;
    }
    if (matched) return true;
    start = haystack.indexOf(parts[0], start + 1);
  }
  return false;
}

function normalize(value) {
  return (
    value
      // NFKC は ″ を ′′ に分解するので、引用符の置き換えを先に行う
      .replace(/[“”„″]/g, '"')
      .replace(/[‘’′]/g, "'")
      .normalize('NFKC')
      .replace(/[‐‑‒–—―−]/g, '-')
      .replace(/[​-‍﻿­]/g, '')
      .replace(/\s+/g, ' ')
      .trim()
      .toLowerCase()
  );
}

// タグを消すだけにする要素。空白に置き換えると <b>foo</b>bar のように語の途中を割り、正しい引用が一致しなくなる
const INLINE_TAGS = new Set([
  'a', 'abbr', 'b', 'bdi', 'bdo', 'cite', 'code', 'data', 'dfn', 'em', 'i', 'kbd', 'mark', 'q', 's', 'samp',
  'small', 'span', 'strong', 'sub', 'sup', 'time', 'u', 'var', 'wbr', 'font', 'tt',
]);

/**
 * HTML から照合に使う本文を取り出す。JSON を埋め込む script の中の文字列は本文として残す。
 * GitHub の issue や Next.js のサイトは本文をそこに埋め込むので、script を丸ごと捨てると取りこぼす（実測）
 */
export function htmlToText(html) {
  const embedded = [];
  const withoutJson = html.replace(
    /<script\b[^>]*type\s*=\s*["']application\/(?:ld\+)?json["'][^>]*>([\s\S]*?)<\/script\s*>/gi,
    (_match, body) => {
      collectJsonStrings(body, embedded);
      return ' ';
    },
  );
  const text = decodeEntities(
    withoutJson
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<(script|style|noscript|template)\b[\s\S]*?<\/\1\s*>/gi, ' ')
      .replace(/<\/?([a-zA-Z][\w-]*)\b[^>]*>/g, (_tag, name) => (INLINE_TAGS.has(name.toLowerCase()) ? '' : ' ')),
  );
  return embedded.length === 0 ? text : `${text}\n${embedded.join('\n')}`;
}

function collectJsonStrings(source, into) {
  let value;
  try {
    value = JSON.parse(source);
  } catch {
    return;
  }
  // 深い入れ子でも再帰で落ちないよう、明示のスタックでたどる
  const stack = [value];
  while (stack.length > 0) {
    const node = stack.pop();
    if (typeof node === 'string') into.push(node);
    else if (Array.isArray(node)) stack.push(...node);
    else if (node !== null && typeof node === 'object') stack.push(...Object.values(node));
  }
}

const NAMED_ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“',
  sbquo: '‚', bdquo: '„', mdash: '—', ndash: '–', minus: '−', hellip: '…', copy: '©', reg: '®', trade: '™',
  laquo: '«', raquo: '»', middot: '·', bull: '•', times: '×', divide: '÷', deg: '°', plusmn: '±', para: '¶',
  sect: '§', euro: '€', pound: '£', yen: '¥', cent: '¢', larr: '←', rarr: '→', uarr: '↑', darr: '↓', harr: '↔',
  le: '≤', ge: '≥', ne: '≠', asymp: '≈', infin: '∞', prime: '′', Prime: '″', thinsp: ' ', ensp: ' ', emsp: ' ',
  zwj: '‍', zwnj: '‌', shy: '­', iexcl: '¡', iquest: '¿', frac12: '½', frac14: '¼', frac34: '¾',
  sup2: '²', sup3: '³', micro: 'µ', dagger: '†', Dagger: '‡', permil: '‰', lsaquo: '‹', rsaquo: '›',
};

function decodeEntities(text) {
  return text.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z][a-z0-9]*);/gi, (entity, body) => {
    let code;
    if (/^#x/i.test(body)) code = parseInt(body.slice(2), 16);
    else if (body.startsWith('#')) code = parseInt(body.slice(1), 10);
    else return NAMED_ENTITIES[body] ?? NAMED_ENTITIES[body.toLowerCase()] ?? entity;
    // 範囲外の数値参照で fromCodePoint が例外を投げると、照合全体が落ちる
    return Number.isInteger(code) && code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : entity;
  });
}

/** text/* は全部を受ける。配布サイトはソースを text/typescript のような個別の型で返す（実測: unpkg） */
export function isTextType(type) {
  if (type.startsWith('text/')) return true;
  return /^application\/(?:[\w.+-]*\+)?(?:json|javascript|ecmascript|xml|typescript|x-typescript|yaml|x-yaml|toml|x-sh)$/.test(
    type,
  );
}

/**
 * 実行ファイルに埋め込まれたスクリプトから文字列を抜き出して読んだ出典もある。
 * UTF-8 として読んで置き換え文字が出たときは latin1 で読んだ本文も足す
 */
async function readLocalFile(path) {
  try {
    const info = await stat(path);
    if (!info.isFile()) return { ok: false, detail: 'ファイルではない' };
    if (info.size > MAX_BODY_BYTES) return { ok: false, detail: 'ファイルが大きすぎる' };
    const buffer = await readFile(path);
    const text = buffer.toString('utf8');
    return { ok: true, text: text.includes('�') ? `${text}\n${buffer.toString('latin1')}` : text };
  } catch (error) {
    return { ok: false, detail: `ファイルを読めない: ${error.code ?? String(error)}` };
  }
}

const GITHUB_THREAD = /^https:\/\/github\.com\/([^/]+)\/([^/]+)\/(?:issues|pull)\/(\d+)(?:[/?#]|$)/;
const GITHUB_MAX_COMMENT_PAGES = 30;

/** 既定の取得。失敗は例外にせず unverifiable の理由として返す */
export async function fetchSourceText(url) {
  const thread = GITHUB_THREAD.exec(url);
  if (thread !== null) return fetchGitHubThread(thread[1], thread[2], thread[3]);
  try {
    const response = await fetch(url, {
      // 本文の読み出しにも効くよう、取得全体に 1 つの期限を掛ける
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: { 'user-agent': 'Mozilla/5.0 (compatible; deep-loop)' },
      redirect: 'follow',
    });
    if (!response.ok) return { ok: false, detail: `取得できない: HTTP ${response.status}` };
    const contentType = response.headers.get('content-type') ?? '';
    const type = contentType.split(';')[0].trim().toLowerCase();
    if (!isTextType(type)) return { ok: false, detail: `本文を取り出せない形式: ${type || '不明'}` };
    const bytes = await readCapped(response);
    if (bytes === null) return { ok: false, detail: '本文が大きすぎる' };
    const html = type.includes('html');
    const text = decode(bytes, charsetOf(contentType, html ? bytes : null));
    if (!html) return { ok: true, text };
    const body = htmlToText(text);
    // スクリプトで描画するページやログイン画面は本文が薄い。not_found と取り違えないよう照合できないものとして扱う
    if (body.replace(/\s+/g, '').length < 200) {
      return { ok: false, detail: '本文がほとんど無い（スクリプトで描画するページかログインが要るページの可能性）' };
    }
    return { ok: true, text: body };
  } catch (error) {
    return { ok: false, detail: `取得できない: ${error instanceof Error ? error.message : String(error)}` };
  }
}

/** 上限を超えたら読み出しを打ち切る。上限を後で確かめるだけだと、終わらない応答を最後まで読もうとする */
async function readCapped(response) {
  if (response.body === null) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

/** Content-Type の charset、無ければ HTML の meta を見る。Shift_JIS や EUC-JP のページを UTF-8 として読むと引用が一致しない */
function charsetOf(contentType, htmlBytes) {
  const fromHeader = /charset\s*=\s*["']?([\w.:-]+)/i.exec(contentType);
  if (fromHeader !== null) return fromHeader[1];
  if (htmlBytes === null) return 'utf-8';
  const head = new TextDecoder('latin1').decode(htmlBytes.subarray(0, 4096));
  return /<meta[^>]+charset\s*=\s*["']?([\w.:-]+)/i.exec(head)?.[1] ?? 'utf-8';
}

function decode(bytes, charset) {
  try {
    return new TextDecoder(charset).decode(bytes);
  } catch {
    return new TextDecoder('utf-8').decode(bytes);
  }
}

/**
 * GitHub の issue と PR は API で本文と全コメントを取る。HTML はコメントが多いと一部しか含まず、
 * 後半のコメントからの引用を無いと誤判定する（実測: コメント 17 件の issue）
 */
async function fetchGitHubThread(owner, repo, number) {
  const base = `https://api.github.com/repos/${owner}/${repo}`;
  const headers = { accept: 'application/vnd.github+json', 'user-agent': 'deep-loop' };
  const token = githubToken();
  if (token !== undefined) headers.authorization = `Bearer ${token}`;
  const get = async (path) => {
    const response = await fetch(`${base}${path}`, { headers, signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    if (!response.ok) {
      const error = new Error(`GitHub API が HTTP ${response.status} を返した`);
      error.status = response.status;
      throw error;
    }
    return response.json();
  };
  try {
    const issue = await get(`/issues/${number}`);
    const texts = [issue.title ?? '', issue.body ?? ''];
    // PR の行ごとのレビューコメントは issue のコメントとは別の API にある
    for (const kind of ['issues', 'pulls']) {
      for (let page = 1; page <= GITHUB_MAX_COMMENT_PAGES; page += 1) {
        let comments;
        try {
          comments = await get(`/${kind}/${number}/comments?per_page=100&page=${page}`);
        } catch (error) {
          // issue に pulls のコメント API は無い（404）
          if (kind === 'pulls' && error.status === 404) break;
          throw error;
        }
        texts.push(...comments.map((comment) => comment.body ?? ''));
        if (comments.length < 100) break;
      }
    }
    return { ok: true, text: texts.join('\n') };
  } catch (error) {
    return { ok: false, detail: `GitHub から取得できない: ${error instanceof Error ? error.message : String(error)}` };
  }
}

let cachedGithubToken;

/** 認証なしの API は 1 時間に 60 回までなので、ログイン済みの gh があれば使う */
function githubToken() {
  if (cachedGithubToken === undefined) {
    const fromEnv = (process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN ?? '').trim();
    if (fromEnv !== '') {
      cachedGithubToken = fromEnv;
    } else {
      const result = spawnSync('gh', ['auth', 'token'], { encoding: 'utf8', timeout: 10_000 });
      const token = result.status === 0 ? result.stdout.trim() : '';
      cachedGithubToken = token === '' ? null : token;
    }
  }
  return cachedGithubToken ?? undefined;
}
