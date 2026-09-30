// deep-loop の hook。
//
// post-write / post-bash: 作業役が主張の一覧（*.claims.json）を書いた直後に引用を照合し、結果を隣の *.checks.json に残す。
//   照合に落ちた引用は additionalContext で作業役本人に返し、その場で直させる（Workflow の中のエージェントにも届く。実測）。
//   作業役は Write ではなく Bash のヒアドキュメントで書くことがある（実測）ので、Bash のコマンドに現れたパスも照合する。
// subagent-stop: 作業役が終わるとき、照合がまだ無いか古い主張の一覧をすべて照合する。書き方によらず、
//   反証役と integrator が照合の結果を必ず読めるようにするため。integrator と最終の書き手は *.checks.json だけを信じる。
// pre-write: 夜間の実行（DEEP_LOOP_DIR が立っている）では、Workflow の作業役の Write / Edit を作業ディレクトリの中に限る。
//   試走で作業役が抜き出した文字列（50MB）をコードの置き場に置いたため。bypassPermissions の下でも deny は効く（実測）。
//   Bash 経由の書き込みはここでは塞げない。
// どの照合も夜間の実行（DEEP_LOOP_DIR）の作業ディレクトリの中の一覧だけを対象にする。plugin は全セッションで有効なので、
// 他の作業で *.claims.json という名前のファイルを書いたときに照合が走らないようにするため。

import { existsSync, realpathSync } from 'node:fs';
import { readdir, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { text } from 'node:stream/consumers';
import { checkClaims } from './claims.mjs';

const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit']);
const CLAIMS_SUFFIX = '.claims.json';

async function main() {
  const mode = process.argv[2];
  let input;
  try {
    input = JSON.parse(await text(process.stdin));
  } catch {
    return;
  }
  if (mode === 'post-write') await postWrite(input);
  else if (mode === 'post-bash') await postBash(input);
  else if (mode === 'subagent-stop') await subagentStop(input);
  else if (mode === 'pre-write') preWrite(input);
}

function runDir() {
  const root = process.env.DEEP_LOOP_DIR;
  return root === undefined || root === '' ? undefined : root;
}

function insideRun(path) {
  const root = runDir();
  return root !== undefined && isInside(realPath(path), realPath(root));
}

async function postWrite(input) {
  if (!WRITE_TOOLS.has(input.tool_name)) return;
  const path = input.tool_input?.file_path;
  if (typeof path !== 'string' || !path.endsWith(CLAIMS_SUFFIX) || !insideRun(path)) return;
  feedback((await verifyFile(path)).join('\n'));
}

// コマンドの文字列からパスを拾うのは近似にとどまる（変数や cd の後の相対パスは拾えない）。
// 拾えなかった一覧は subagent-stop が照合するので、ここは作業役にその場で返すための補助である
async function postBash(input) {
  const command = input.tool_input?.command;
  if (typeof command !== 'string' || !command.includes(CLAIMS_SUFFIX) || runDir() === undefined) return;
  const paths = [...new Set(command.match(/[^\s'"`<>|;&()]+\.claims\.json/g) ?? [])]
    .map((path) => resolve(input.cwd ?? process.cwd(), path))
    .filter((path) => existsSync(path) && insideRun(path));
  if (paths.length === 0) return;
  const lines = [];
  for (const path of paths) lines.push(...(await verifyFile(path)));
  feedback(lines.join('\n'));
}

async function subagentStop(input) {
  const root = runDir();
  if (root === undefined || input.agent_type !== 'workflow-subagent') return;
  const rounds = join(root, 'rounds');
  if (!existsSync(rounds)) return;
  for (const round of await readdir(rounds)) {
    const dir = join(rounds, round);
    let names;
    try {
      names = await readdir(dir);
    } catch {
      continue;
    }
    for (const name of names.filter((entry) => entry.endsWith(CLAIMS_SUFFIX))) {
      const path = join(dir, name);
      const checks = checksPathOf(path);
      if (existsSync(checks) && (await stat(checks)).mtimeMs >= (await stat(path)).mtimeMs) continue;
      await verifyFile(path);
    }
  }
}

function checksPathOf(path) {
  return `${path.slice(0, -CLAIMS_SUFFIX.length)}.checks.json`;
}

/**
 * 照合して checks を書き、作業役に返す文面を行で返す。
 * 照合を始める前に古い checks を消し、書くときは一時ファイルから置き換える。hook が時間切れで止まっても、
 * 前の一覧の照合結果が今の結果として読まれない（checks が無ければ、読む側は未照合として扱う）
 */
async function verifyFile(path) {
  const checksPath = checksPathOf(path);
  await rm(checksPath, { force: true });
  let entries;
  try {
    entries = JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    return [`deep-loop: ${path} を JSON として読めない（${error.message}）。主張の配列として書き直す。`];
  }
  if (!Array.isArray(entries)) {
    return [`deep-loop: ${path} は配列ではない。主張の配列として書き直す。`];
  }

  const checks = await checkClaims(entries);
  const temporary = join(dirname(checksPath), `.${basename(checksPath)}.${process.pid}.tmp`);
  try {
    await writeFile(temporary, `${JSON.stringify(checks, null, 2)}\n`);
    await rename(temporary, checksPath);
  } catch (error) {
    await rm(temporary, { force: true });
    return [`deep-loop: 照合の結果を ${checksPath} に書けなかった（${error.message}）。`];
  }
  const count = (status) => checks.filter((check) => check.status === status).length;
  const failed = checks
    .map((check, index) => ({ check, index }))
    .filter(({ check }) => check.status !== 'verified');
  const lines = [
    `deep-loop citation check for ${path}: verified ${count('verified')}, not_found ${count('not_found')}, unverifiable ${count('unverifiable')}.`,
  ];
  if (failed.length > 0) {
    lines.push(
      'Claims that did not verify (index, status, reason, quote):',
      ...failed
        .slice(0, 40)
        .map(({ check, index }) => `- [${index}] ${check.status}: ${check.detail ?? ''} | ${check.quote.slice(0, 120)}`),
      'For not_found: re-read the source and copy the passage character for character, or drop the claim and its statement from your notes.',
      'For unverifiable: prefer another source that can be read as text; otherwise keep it, and it will be treated as unverified.',
      'Rewrite the claims file with the Write tool after fixing it; it is checked again on every write.',
    );
  }
  return lines;
}

function feedback(additionalContext) {
  if (additionalContext === '') return;
  process.stdout.write(
    JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext } }),
  );
}

function preWrite(input) {
  const root = runDir();
  if (root === undefined) return;
  if (input.agent_type !== 'workflow-subagent') return;
  if (!WRITE_TOOLS.has(input.tool_name)) return;
  // 判定の途中で落ちると hook は通してしまう（fail-open）ので、例外のときは拒否に倒す
  try {
    const path = input.tool_input?.file_path ?? input.tool_input?.notebook_path;
    if (typeof path !== 'string') return;
    if (isInside(realPath(path), realPath(root))) return;
    deny(`deep-loop: workers may write only under ${root} (use your scratch_dir for intermediate files). Repositories are read-only.`);
  } catch (error) {
    deny(`deep-loop: could not check the write target (${error.message}); refusing the write.`);
  }
}

function deny(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
    }),
  );
}

/**
 * シンボリックリンクを解決した実パス。まだ無いファイルは、存在する最も近い祖先を解決して残りをつなぐ。
 * 解決せずに比べると、作業ディレクトリの中に外を指すリンクを作ってその下へ書く抜け道ができる（試走で見つかった）
 */
function realPath(path) {
  let current = resolve(path);
  const rest = [];
  for (;;) {
    try {
      return join(realpathSync(current), ...rest);
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
      const parent = dirname(current);
      if (parent === current) return resolve(path);
      rest.unshift(basename(current));
      current = parent;
    }
  }
}

function isInside(path, base) {
  return path === base || path.startsWith(base + sep);
}

await main();
