// node --test agents/plugins/deep-loop/scripts/ で回す。ネットワークにも本物の claude にも出ない
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { checkClaims, containsQuote, fetchSourceText, htmlToText, isTextType } from './claims.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const temp = (prefix) => mkdtempSync(join(tmpdir(), prefix));
const originalFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = originalFetch;
});

test('表記揺れを無視し、... で省いた箇所は近くに順に並んでいればよい', () => {
  assert.equal(containsQuote('Tokens  expire\n“one hour” — see RFC.', 'tokens expire "one hour" - see rfc'), true);
  assert.equal(containsQuote('Step one here. Step two here. Step three here.', 'Step one here. ... Step three here'), true);
  assert.equal(containsQuote('Step one here. Step two here. Step three here.', 'Step three here ... Step one here'), false);
  assert.equal(containsQuote('有効期限は１時間（ＵＴＣ）', '有効期限は1時間(UTC)'), true);
  assert.equal(containsQuote('Tokens expire after one hour.', 'Tokens last for an hour'), false);
  // 離れた文をつないだ引用は一致させない
  const far = `Alpha statement here. ${'x'.repeat(3000)} Omega statement here.`;
  assert.equal(containsQuote(far, 'Alpha statement here. ... Omega statement here.'), false);
});

test('インライン要素をまたぐ引用と、名前付きの文字参照をまたぐ引用が一致する', () => {
  assert.equal(containsQuote(htmlToText('<p>Use <b>foo</b>bar. Then <code>baz</code>()</p>'), 'Use foobar. Then baz()'), true);
  assert.equal(
    containsQuote(htmlToText('<p>It&rsquo;s the author&rsquo;s call &mdash; always.</p>'), "It's the author's call - always."),
    true,
  );
  // ブロック要素の境目は空白になる
  assert.equal(containsQuote(htmlToText('<li>first item</li><li>second item</li>'), 'first item second item'), true);
});

test('範囲外の数値文字参照と深い入れ子の埋め込み JSON で落ちない', () => {
  assert.doesNotThrow(() => htmlToText('<p>bad &#x110000; &#99999999; ref</p>'));
  let deep = '"leaf text inside deep json"';
  for (let i = 0; i < 20000; i += 1) deep = `[${deep}]`;
  const text = htmlToText(`<script type="application/json">${deep}</script>`);
  assert.equal(containsQuote(text, 'leaf text inside deep json'), true);
});

test('JSON を埋め込む script の文字列を本文に残し、実行用の script は捨てる', () => {
  const payload = JSON.stringify({ issue: { body: 'Both resolved correctly as the top-level process' } });
  const html = `<div></div><script type="application/json">${payload}</script><script>var secret = 1</script>`;
  const text = htmlToText(html);
  assert.equal(containsQuote(text, 'Both resolved correctly as the top-level process'), true);
  assert.equal(text.includes('var secret'), false);
});

test('text/* と文字の application 型だけを本文として読む', () => {
  for (const type of ['text/typescript', 'text/html', 'application/json', 'application/ld+json']) {
    assert.equal(isTextType(type), true, type);
  }
  for (const type of ['application/pdf', 'image/png', 'application/octet-stream']) {
    assert.equal(isTextType(type), false, type);
  }
});

test('本文を取れた出典だけを verified / not_found で判定し、短すぎる引用と形の崩れた主張は照合できないとする', async () => {
  const dir = temp('deep-loop-');
  const file = join(dir, 'auth.ts');
  writeFileSync(file, 'export const TOKEN_TTL_SECONDS = 3600;\n');
  const fetchText = async (url) => {
    if (url.endsWith('.pdf')) return { ok: false, detail: 'pdf' };
    if (url.endsWith('/throws')) throw new RangeError('boom');
    return { ok: true, text: 'The API accepts OAuth 2.0 client credentials.' };
  };

  const checks = await checkClaims(
    [
      { claim: 'a', source: 'https://example.com/doc', quote: 'accepts OAuth 2.0' },
      { claim: 'b', source: 'https://example.com/doc', quote: 'accepts SAML assertions' },
      { claim: 'c', source: 'https://example.com/x.pdf', quote: 'anything at all here' },
      { claim: 'd', source: file, quote: 'TOKEN_TTL_SECONDS = 3600' },
      { claim: 'e', source: 'relative/path.ts', quote: 'anything at all here' },
      { claim: 'f', source: 'https://example.com/doc' },
      { claim: 'g', source: 'https://example.com/doc', quote: 'API' },
      // 1 件の例外で、他の主張の照合結果まで失わない
      { claim: 'h', source: 'https://example.com/throws', quote: 'anything at all here' },
    ],
    fetchText,
  );
  assert.deepEqual(
    checks.map((check) => check.status),
    ['verified', 'not_found', 'unverifiable', 'verified', 'unverifiable', 'unverifiable', 'unverifiable', 'unverifiable'],
  );
});

test('Content-Type の charset で本文を復号し、上限を超える本文は読み切らずに断る', async () => {
  const text = '有効期限は一時間である。'.repeat(30);
  globalThis.fetch = async () =>
    new Response(new TextEncoder().encode(text), { headers: { 'content-type': 'text/plain; charset=utf-8' } });
  const source = await fetchSourceText('https://example.com/ja');
  assert.equal(source.ok && containsQuote(source.text, '有効期限は一時間である。'), true);

  globalThis.fetch = async () =>
    new Response(new Uint8Array(30_000_000), { headers: { 'content-type': 'text/plain' } });
  assert.deepEqual(await fetchSourceText('https://example.com/huge'), { ok: false, detail: '本文が大きすぎる' });
});

function runHook(mode, input, env = {}) {
  return spawnSync(process.execPath, [join(here, 'hook.mjs'), mode], {
    input: JSON.stringify(input),
    encoding: 'utf8',
    env: { ...process.env, DEEP_LOOP_DIR: '', ...env },
  });
}

test('pre-write は夜間の実行で作業役の書き込みを作業ディレクトリの中に限り、リンクの抜け道も塞ぐ', () => {
  const root = temp('deep-loop-run-');
  const outside = temp('deep-loop-outside-');
  mkdirSync(join(root, 'rounds', 'r01', 't.work'), { recursive: true });
  symlinkSync(outside, join(root, 'rounds', 'r01', 't.work', 'escape'));
  const write = (path, agentType = 'workflow-subagent') => ({
    tool_name: 'Write',
    agent_type: agentType,
    tool_input: { file_path: path, content: 'x' },
  });
  const denied = (result) => result.stdout.includes('"permissionDecision":"deny"');

  assert.equal(denied(runHook('pre-write', write('/home/u/repo/src/a.ts'), { DEEP_LOOP_DIR: root })), true);
  assert.equal(denied(runHook('pre-write', write(join(root, 'rounds/r01/a.md')), { DEEP_LOOP_DIR: root })), false);
  assert.equal(
    denied(runHook('pre-write', write(join(root, 'rounds/r01/t.work/escape/stolen.txt')), { DEEP_LOOP_DIR: root })),
    true,
  );
  // 指揮役（メインのセッション）と夜間の実行の外は縛らない
  assert.equal(denied(runHook('pre-write', write('/home/u/repo/a.ts', null), { DEEP_LOOP_DIR: root })), false);
  assert.equal(denied(runHook('pre-write', write('/home/u/repo/a.ts'))), false);
});

test('post-write は作業ディレクトリの中の主張の一覧を照合して隣に checks を書き、外のものは照合しない', () => {
  const root = temp('deep-loop-claims-');
  const source = join(root, 'source.txt');
  writeFileSync(source, 'The retry budget is three attempts.\n');
  const claims = join(root, 'task.claims.json');
  writeFileSync(
    claims,
    JSON.stringify([
      { claim: '3 回', source, quote: 'The retry budget is three attempts' },
      { claim: '捏造', source, quote: 'The retry budget is unlimited' },
    ]),
  );
  const input = { tool_name: 'Write', tool_input: { file_path: claims } };

  assert.equal(runHook('post-write', input).stdout, '');
  assert.equal(existsSync(join(root, 'task.checks.json')), false);

  const output = JSON.parse(runHook('post-write', input, { DEEP_LOOP_DIR: root }).stdout);
  assert.match(output.hookSpecificOutput.additionalContext, /verified 1, not_found 1/);
  const checks = JSON.parse(readFileSync(join(root, 'task.checks.json'), 'utf8'));
  assert.deepEqual(
    checks.map((check) => check.status),
    ['verified', 'not_found'],
  );
});

test('post-bash は Bash のコマンドに現れた主張の一覧を照合する', () => {
  const root = temp('deep-loop-bash-');
  const source = join(root, 'source.txt');
  writeFileSync(source, 'Workers run on Sonnet.\n');
  writeFileSync(join(root, 'task.claims.json'), JSON.stringify([{ claim: 'x', source, quote: 'Workers run on Sonnet' }]));

  const result = runHook(
    'post-bash',
    { tool_name: 'Bash', cwd: root, tool_input: { command: "cat > task.claims.json <<'EOF'\n[]\nEOF" } },
    { DEEP_LOOP_DIR: root },
  );
  assert.match(JSON.parse(result.stdout).hookSpecificOutput.additionalContext, /verified 1/);
  assert.equal(JSON.parse(readFileSync(join(root, 'task.checks.json'), 'utf8'))[0].status, 'verified');
});

test('subagent-stop は照合がまだ無いか古い主張の一覧だけを照合する', () => {
  const root = temp('deep-loop-stop-');
  const round = join(root, 'rounds', 'r01');
  mkdirSync(round, { recursive: true });
  const source = join(root, 'source.txt');
  writeFileSync(source, 'The budget is fixed for now.\n');
  writeFileSync(join(round, 'a.claims.json'), JSON.stringify([{ claim: 'x', source, quote: 'The budget is fixed' }]));
  const done = join(round, 'b.claims.json');
  writeFileSync(done, JSON.stringify([{ claim: 'y', source, quote: 'The budget is fixed' }]));
  writeFileSync(join(round, 'b.checks.json'), '["already checked"]\n');
  const past = new Date(Date.now() - 60_000);
  utimesSync(done, past, past);

  runHook('subagent-stop', { agent_type: 'workflow-subagent' }, { DEEP_LOOP_DIR: root });

  assert.equal(JSON.parse(readFileSync(join(round, 'a.checks.json'), 'utf8'))[0].status, 'verified');
  assert.deepEqual(JSON.parse(readFileSync(join(round, 'b.checks.json'), 'utf8')), ['already checked']);
});

// runner は偽の claude を PATH に置いて通しで確かめる
function runner(args, { input, env = {} } = {}) {
  return spawnSync(join(here, 'deep-loop'), args, {
    input: input ?? '',
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
}

function fakeClaude({ hang = false } = {}) {
  const bin = temp('deep-loop-bin-');
  const script = join(bin, 'claude');
  writeFileSync(
    script,
    [
      '#!/usr/bin/env bash',
      'cgroup="/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)"',
      'printf "%s\\n" "$PWD" "$CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS" "$DEEP_LOOP_DIR" "$(cat "$cgroup/memory.max")" "$(cat "$cgroup/memory.swap.max")" "$GRADLE_OPTS" "$@" > "$DEEP_LOOP_DIR/fake-claude.txt"',
      // 親を失っても残り続ける Gradle の test worker の代わり
      'setsid sleep 300 </dev/null >/dev/null 2>&1 &',
      'echo $! > "$DEEP_LOOP_DIR/orphan.pid"',
      ...(hang ? ['sleep 300'] : []),
      'echo \'{"total_cost_usd": 1.5, "result": "ok"}\'',
      '',
    ].join('\n'),
  );
  chmodSync(script, 0o755);
  return `${bin}:${process.env.PATH}`;
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitFor(path) {
  for (let i = 0; i < 100 && !existsSync(path); i += 1) {
    await new Promise((resolveWait) => setTimeout(resolveWait, 50));
  }
}

test('runner は repo を cwd にし、待ちの上限を外して claude -p をメモリの上限付きで切り離して走らせ、残った子を片づける', async () => {
  const root = temp('deep-loop-root-');
  const repo = temp('deep-loop-repo-');
  const env = { DEEP_LOOP_ROOT: root, PATH: fakeClaude(), DEEP_LOOP_MEMORY_MAX: '1G', GRADLE_OPTS: '-Xmx64m' };

  const started = runner(['start', 'demo', '--repo', repo, '--rounds', '2'], { input: '# brief\n', env });
  assert.equal(started.status, 0, started.stderr);
  const dir = join(root, 'demo');
  await waitFor(join(dir, 'exit_code'));

  assert.equal(readFileSync(join(dir, 'exit_code'), 'utf8').trim(), '0');
  const [cwd, ceiling, runDir, memoryMax, swapMax, gradleOpts, ...args] = readFileSync(join(dir, 'fake-claude.txt'), 'utf8')
    .trim()
    .split('\n');
  assert.equal(cwd, repo);
  assert.equal(ceiling, '0');
  assert.equal(runDir, dir);
  assert.equal(memoryMax, String(1024 ** 3));
  assert.equal(swapMax, '0');
  assert.equal(gradleOpts, '-Xmx64m -Dorg.gradle.daemon=false');
  assert.equal(alive(Number(readFileSync(join(dir, 'orphan.pid'), 'utf8'))), false);
  assert.equal(args.at(-1), `/deep-loop:run ${dir}`);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, 'meta.json'), 'utf8')), { maxRounds: 2, repos: [repo] });

  const custom = runner(
    ['start', 'custom', '--model', 'verifier=sonnet', '--effort', 'worker=high', '--model', 'writer=opus'],
    { input: '# brief\n', env },
  );
  assert.equal(custom.status, 0, custom.stderr);
  await waitFor(join(root, 'custom', 'exit_code'));
  assert.deepEqual(JSON.parse(readFileSync(join(root, 'custom', 'meta.json'), 'utf8')), {
    maxRounds: 3,
    repos: [],
    models: { verifier: 'sonnet', writer: 'opus' },
    efforts: { worker: 'high' },
  });
  assert.notEqual(runner(['start', 'bad-model', '--model', 'boss=opus'], { input: '# brief\n', env }).status, 0);

  const status = runner(['status', 'demo'], { env });
  assert.match(status.stdout, /停止/);
  assert.match(status.stdout, /費用: 1\.50 USD/);
});

test('runner の stop は claude と、プロセスグループの外に出た子まで止める', async () => {
  const root = temp('deep-loop-root-');
  const env = { DEEP_LOOP_ROOT: root, PATH: fakeClaude({ hang: true }) };

  assert.equal(runner(['start', 'hang'], { input: '# brief\n', env }).status, 0);
  const dir = join(root, 'hang');
  await waitFor(join(dir, 'orphan.pid'));
  const orphan = Number(readFileSync(join(dir, 'orphan.pid'), 'utf8'));
  assert.equal(alive(orphan), true);

  const stopped = runner(['stop', 'hang'], { env });
  assert.equal(stopped.status, 0, stopped.stderr);
  assert.equal(alive(orphan), false);
  assert.match(runner(['status', 'hang'], { env }).stdout, /停止/);
});

test('runner は読めない --at、値の無い --at、空の brief、読めないメモリの上限、同じ名前の start を、作業ディレクトリを残さずに断る', () => {
  const root = temp('deep-loop-root-');
  const env = { DEEP_LOOP_ROOT: root, PATH: fakeClaude() };

  for (const args of [['start', 'bad-at', '--at', '25:99'], ['start', 'no-at', '--at']]) {
    const result = runner(args, { input: '# brief\n', env });
    assert.notEqual(result.status, 0, args.join(' '));
    assert.equal(existsSync(join(root, args[1])), false, args.join(' '));
  }
  const empty = runner(['start', 'empty'], { input: '', env });
  assert.notEqual(empty.status, 0);
  assert.equal(existsSync(join(root, 'empty')), false);

  const badMemory = runner(['start', 'bad-memory'], { input: '# brief\n', env: { ...env, DEEP_LOOP_MEMORY_MAX: 'lots' } });
  assert.notEqual(badMemory.status, 0);
  assert.equal(existsSync(join(root, 'bad-memory')), false);

  mkdirSync(join(root, 'taken'), { recursive: true });
  writeFileSync(join(root, 'taken', 'brief.md'), '# brief\n');
  assert.notEqual(runner(['start', 'taken'], { input: '# brief\n', env }).status, 0);
});

test('runner は再利用された pid を走行中と見なさず、消えたリポジトリでは再開しない', () => {
  const root = temp('deep-loop-root-');
  const dir = join(root, 'stale');
  mkdirSync(join(dir, 'rounds'), { recursive: true });
  writeFileSync(join(dir, 'brief.md'), '# brief\n');
  writeFileSync(join(dir, 'meta.json'), JSON.stringify({ maxRounds: 3, repos: ['/nonexistent/repo'] }));
  // 生きている無関係なプロセス（このテスト自身）の pid と、合わない開始時刻
  writeFileSync(join(dir, 'run.pid'), `${process.pid} 1\n`);
  const env = { DEEP_LOOP_ROOT: root, PATH: fakeClaude() };

  assert.match(runner(['status', 'stale'], { env }).stdout, /停止/);
  assert.notEqual(runner(['stop', 'stale'], { env }).status, 0);
  const resumed = runner(['resume', 'stale'], { env });
  assert.notEqual(resumed.status, 0);
  assert.match(resumed.stderr, /\/nonexistent\/repo が無い/);
});
