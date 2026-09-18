#!/usr/bin/env node
// CLAUDE.md の規約のうち、機械的に判定できるものを Claude Code hook で確認する。
//   bash: PreToolUse (Bash)。git config --global、新しく作るブランチの名前、コミットメッセージを見て、規約に反していれば実行を止める
//   sync: PostToolUse (Write|Edit)。agents/claude と agents/codex の対応する文書がずれたら知らせる
//   stop: Stop。dotfiles で設定を変えたあとの sheldon lock と mise install、plugin の version 上げ忘れを拾う
// hook 自身の不具合で作業を止めないよう、判定に失敗したときは常に exit 0 で通す。
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import os from "node:os";
import path from "node:path";

// 誤検知で手が止まったときの逃げ道。コマンドの先頭に付けると bash の確認を飛ばす
const SKIP_MARKER = /\bGUARD_SKIP=1\b/;
const CONVENTIONAL = /^(?:build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(?:\([^)]+\))?!?: \S/;
const JAPANESE = /[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]/;
const BRANCH_RULE = /^wakwak3125\/[a-z0-9]+(?:-[a-z0-9]+)*$/;
// 個人リポジトリの置き場。org のリポジトリはチケット ID 起点など別の規約があるため、ブランチ名はここでだけ強制する
const PERSONAL_ROOT = path.join(os.homedir(), "src", "github.com", "wakwak3125");
// 報告が長いと会話のトークンを圧迫するので件数を絞る
const MAX_LINES = 8;

async function readStdin() {
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

function git(cwd, args) {
  try {
    return execFileSync("git", ["-C", cwd, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

// git() は前後の空白を落とすため、行頭 2 文字に状態が入る --porcelain の解析には使えない
function gitLines(cwd, args) {
  try {
    return execFileSync("git", ["-C", cwd, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    })
      .split("\n")
      .filter((line) => line.length > 0);
  } catch {
    return [];
  }
}

function block(lines) {
  process.stderr.write(`${lines.slice(0, MAX_LINES + 1).join("\n")}\n`);
  process.exit(2);
}

function unquote(raw) {
  if (raw.startsWith("'") && raw.endsWith("'")) return raw.slice(1, -1);
  if (raw.startsWith('"') && raw.endsWith('"')) return raw.slice(1, -1).replace(/\\(["\\$`])/g, "$1");
  return raw;
}

// dotfiles 固有の規約を適用してよいかを中身で判定する。worktree では作業ツリーの名前が枝名になるため、ディレクトリ名では見分けられない
function isDotfiles(root) {
  return !!root && existsSync(path.join(root, "gitconfig")) && existsSync(path.join(root, "agents/claude/global/CLAUDE.md"));
}

// ---- bash: PreToolUse (Bash) ----

// git config の書き込みだけを拾う。値を読むだけの呼び出しは通す
function checkGitConfig(command, root) {
  if (!isDotfiles(root)) return [];
  const readOnly = /(?:^|\s)(?:--get\b|--get-all\b|--get-regexp\b|--get-urlmatch\b|-l\b|--list\b|--show-origin\b|--show-scope\b)/;
  for (const [, args] of command.matchAll(/(?:^|[;&|(\n])\s*(?:\w+=\S*\s+)*git\s+config\s+([^\n;&|]*)/g)) {
    if (!/(?:^|\s)--global(?:\s|=|$)/.test(args) || readOnly.test(args)) continue;
    return [
      "guard: dotfiles では git config --global で ~/.gitconfig を書き換えないでください。",
      "~/.gitconfig は dotfiles の gitconfig への symlink です。リポジトリの gitconfig を直接編集してください。",
      "$HOME の展開が必要な設定だけは bootstrap.sh が ~/.gitconfig_local へ書き出します。",
    ];
  }
  return [];
}

function branchExists(cwd, name) {
  return !!git(cwd, ["rev-parse", "--verify", "--quiet", `refs/heads/${name}`]);
}

// heredoc の本文を同じ長さの空白に置き換える。PR 本文や埋め込みスクリプトに書かれた git commit を命令と取り違えないため。
// 長さを保つのは、ここで得た位置を元のコマンドにそのまま当ててメッセージを取り出すため
function maskHeredocs(command) {
  return command.replace(/(<<-?\s*['"]?(\w+)['"]?[^\n]*\n)([\s\S]*?)(\n[ \t]*\2\b)/g, (_, head, _tag, body, tail) => {
    return head + body.replace(/[^\n]/g, " ") + tail;
  });
}

function expandPath(raw, vars) {
  let p = unquote(raw).replace(/\$\{(\w+)\}|\$(\w+)/g, (m, a, b) => {
    const name = a || b;
    if (name === "HOME") return os.homedir();
    return name in vars ? vars[name] : m;
  });
  p = p.replace(/^~(?=\/|$)/, os.homedir());
  // 展開しきれない変数やコマンド置換が残るなら、行き先は分からない
  return /[$`*?]/.test(p) ? null : p;
}

// git が実際に動くディレクトリを、手前の cd と代入、-C から求める。
// hook に渡る cwd だけで見ると、main に居るセッションから worktree へコミットしたときに「main へ直接コミット」と誤って止めてしまう。
// 分からないときは null を返し、呼び出し側は確認を飛ばす
function effectiveDir(before, dashC, cwd) {
  const vars = {};
  let dir = cwd;
  const re = /(?:^|[;&|(\n])\s*(?:(\w+)=("[^"]*"|'[^']*'|[^\s;&|)]*)(?=\s*(?:[;&\n]|$))|cd\s+("[^"]*"|'[^']*'|[^\s;&|)]+))/g;
  for (const [, name, value, target] of before.matchAll(re)) {
    if (name) {
      const v = expandPath(value, vars);
      if (v === null) delete vars[name];
      else vars[name] = v;
      continue;
    }
    const to = expandPath(target, vars);
    if (to === null || to === "-") dir = null;
    else if (path.isAbsolute(to)) dir = to;
    else if (dir !== null) dir = path.resolve(dir, to);
  }
  if (dashC) {
    const to = expandPath(dashC, vars);
    if (to === null) return null;
    if (path.isAbsolute(to)) return to;
    return dir === null ? null : path.resolve(dir, to);
  }
  return dir;
}

const GIT_PREFIX = String.raw`(?:^|[;&|(\n])\s*(?:\w+=\S*\s+)*git\s+(?:-C\s+("[^"]*"|'[^']*'|\S+)\s+)?`;
// git branch で枝を作るときにも付けられる長いオプション。これ以外の長いオプション (--merged、--contains など) は一覧や設定の操作で、枝は増えない
const BRANCH_CREATE_FLAGS = /^--(?:force|track(?:=.*)?|no-track|quiet|create-reflog|recurse-submodules)$/;

// これから作られるブランチ名だけを拾う。既存ブランチへの切り替えまで見ると、規約を決める前に作った枝で止まってしまう
function extractNewBranches(command, cwd) {
  const found = [];
  const masked = maskHeredocs(command);
  const re = new RegExp(`${GIT_PREFIX}(switch|checkout|branch|wt)\\b([^\\n;&|]*)`, "g");
  for (const m of masked.matchAll(re)) {
    const [, dashC, sub, rest] = m;
    // 2>&1 のようなリダイレクトは引数ではない
    const args = rest.trim().split(/\s+/).filter((a) => a && !/^(?:\d*[<>]|&>)/.test(a));
    if (args.some((a) => a === "--help" || a === "-h")) continue;
    const dir = effectiveDir(masked.slice(0, m.index), dashC, cwd);
    if (dir === null) continue;
    if (sub === "switch" || sub === "checkout") {
      const i = args.findIndex((a) => ["-c", "-C", "-b", "-B", "--create"].includes(a));
      if (i >= 0 && args[i + 1]) found.push({ name: unquote(args[i + 1]), dir });
    } else if (sub === "branch") {
      // 削除・改名・一覧は新しい枝を作らない
      if (args.some((a) => /^-(?:d|D|m|M|c|C|r|a|v|vv|l|u)$/.test(a) || (a.startsWith("--") && !BRANCH_CREATE_FLAGS.test(a)))) continue;
      const first = args.find((a) => !a.startsWith("-"));
      if (first) found.push({ name: unquote(first), dir });
    } else if (sub === "wt") {
      // git wt は既存 worktree への移動にも使うので、まだ無い枝を指したときだけ規約を見る
      const first = args.find((a) => !a.startsWith("-"));
      if (first && !branchExists(dir, unquote(first))) found.push({ name: unquote(first), dir });
    }
  }
  return found;
}

function isPersonal(root) {
  return root === PERSONAL_ROOT || root.startsWith(`${PERSONAL_ROOT}${path.sep}`);
}

function checkBranchNames(command, cwd) {
  const bad = extractNewBranches(command, cwd)
    .filter(({ name, dir }) => !BRANCH_RULE.test(name) && isPersonal(git(dir, ["rev-parse", "--show-toplevel"])))
    .map(({ name }) => name);
  if (bad.length === 0) return [];
  return [
    `guard: ブランチ名が規約に合いません: ${bad.join(", ")}`,
    "個人リポジトリのブランチは wakwak3125/ を prefix とし、ケバブケースで命名します (例: wakwak3125/awsome-feature)。",
  ];
}

// git commit -m "$(cat <<'EOF' ... EOF)" と -m "..." / --message=... を拾う。-m は複数渡せて段落として連結されるので全部つなぐ。
// -F や --amend --no-edit はメッセージがコマンドに現れないので対象外にする
function extractCommitMessage(text) {
  const parts = [];
  const re = /(?:^|\s)(?:-[a-zA-Z]*m|--message)(?:=|\s+)(?:"?\$\(\s*cat\s+<<-?\s*['"]?(\w+)['"]?[^\n]*\n([\s\S]*?)\n\s*\1\s*\)"?|("(?:[^"\\]|\\.)*"|'[^']*'))/g;
  for (const [, , heredoc, quoted] of text.matchAll(re)) parts.push(heredoc ?? unquote(quoted));
  return parts.length > 0 ? parts.join("\n\n") : null;
}

function defaultBranch(cwd) {
  const head = git(cwd, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]);
  return head ? head.replace(/^origin\//, "") : "";
}

function checkCommit(command, cwd) {
  const masked = maskHeredocs(command);
  const commits = [...masked.matchAll(new RegExp(`${GIT_PREFIX}commit\\b`, "g"))];
  const lines = [];

  commits.forEach((m, i) => {
    const before = masked.slice(0, m.index);
    const dir = effectiveDir(before, m[1], cwd);
    // 同じコマンドの中で先に枝を切り替えていれば、実行時の枝は今の枝と違う
    const switched = new RegExp(`${GIT_PREFIX}(?:switch|checkout|wt)\\b`).test(before);
    if (dir !== null && !switched) {
      const current = git(dir, ["rev-parse", "--abbrev-ref", "HEAD"]);
      const base = defaultBranch(dir);
      if (current && base && current === base) {
        lines.push(`guard: ${base} へ直接コミットしようとしています。作業用のブランチを切ってください。`);
      }
    }

    const end = i + 1 < commits.length ? commits[i + 1].index : command.length;
    // 次の命令の -m を拾わないよう、この git commit の引数だけを見る
    const own = /^(?:[^;&|\n"']|"(?:[^"\\]|\\.)*"|'[^']*')*/.exec(command.slice(m.index + m[0].length, end))[0];
    const message = extractCommitMessage(own);
    if (!message) return;
    const subject = message.split("\n")[0].trim();
    // fixup! などは autosquash で元のコミットに畳まれるので、件名の元の部分だけを見て trailer は求めない
    const autosquash = /^(?:(?:fixup|squash|amend)! )+/.exec(subject);
    const body = autosquash ? subject.slice(autosquash[0].length) : subject;
    if (!CONVENTIONAL.test(body)) {
      lines.push(`guard: コミットの件名が conventional commits の形式ではありません: ${subject}`);
      lines.push("  形式: <type>(<scope>): <説明>  type は feat/fix/docs/style/refactor/perf/test/build/ci/chore/revert");
    } else if (!JAPANESE.test(body)) {
      lines.push(`guard: コミットの件名を日本語で書いてください: ${subject}`);
    }
    if (!autosquash && !/Co-Authored-By:.*@anthropic\.com/i.test(message)) {
      lines.push("guard: コミットメッセージの末尾に Co-Authored-By の行がありません。");
    }
  });
  return [...new Set(lines)];
}

async function runBash(input) {
  const command = input.tool_input?.command;
  if (typeof command !== "string" || SKIP_MARKER.test(command)) return;
  const cwd = input.cwd || process.cwd();
  const root = git(cwd, ["rev-parse", "--show-toplevel"]);

  const lines = [
    ...checkGitConfig(command, root),
    ...checkBranchNames(command, cwd),
    ...checkCommit(command, cwd),
  ];
  if (lines.length === 0) return;
  lines.push("誤検知であればコマンドの先頭に GUARD_SKIP=1 を付けて実行してください。");
  block(lines);
}

// ---- sync: PostToolUse (Write|Edit) ----

// エージェント固有と明示した見出し。ここだけは claude 側と codex 側で内容が分かれてよい
const AGENT_ONLY = /[(（](?:Claude Code|Codex)\s*固有[)）]/;

function counterpart(rel) {
  if (rel.startsWith("agents/claude/") && rel.endsWith("CLAUDE.md")) {
    return rel.replace("agents/claude/", "agents/codex/").replace(/CLAUDE\.md$/, "AGENTS.md");
  }
  if (rel.startsWith("agents/codex/") && rel.endsWith("AGENTS.md")) {
    return rel.replace("agents/codex/", "agents/claude/").replace(/AGENTS\.md$/, "CLAUDE.md");
  }
  return null;
}

// 最上位の見出しはファイル名そのもの、エージェント固有のセクションは意図した違いなので、どちらも比較から外す
function normalize(text) {
  const out = [];
  let skipping = false;
  for (const line of text.split("\n")) {
    if (/^#{1,6}\s/.test(line)) {
      skipping = AGENT_ONLY.test(line);
      if (/^#\s/.test(line)) continue;
    }
    if (skipping) continue;
    out.push(line.trimEnd());
  }
  return out.join("\n").replace(/\n{2,}/g, "\n").trim();
}

function onlyIn(a, b) {
  const other = new Set(b.split("\n"));
  return a.split("\n").filter((l) => l.trim() && !other.has(l));
}

async function runSync(input) {
  const filePath = input.tool_input?.file_path;
  if (typeof filePath !== "string") return;
  const cwd = input.cwd || process.cwd();
  const root = git(cwd, ["rev-parse", "--show-toplevel"]);
  if (!isDotfiles(root)) return;

  const rel = path.relative(root, filePath).split(path.sep).join("/");
  const otherRel = counterpart(rel);
  if (!otherRel) return;
  const otherPath = path.join(root, otherRel);
  if (!existsSync(filePath) || !existsSync(otherPath)) return;

  const mine = normalize(readFileSync(filePath, "utf8"));
  const theirs = normalize(readFileSync(otherPath, "utf8"));
  if (mine === theirs) return;

  const lines = [`guard: ${rel} と ${otherRel} の内容がずれています。両方に同じ変更を入れてください。`];
  for (const l of onlyIn(mine, theirs).slice(0, MAX_LINES / 2)) lines.push(`- ${rel} にのみある: ${l}`);
  for (const l of onlyIn(theirs, mine).slice(0, MAX_LINES / 2)) lines.push(`- ${otherRel} にのみある: ${l}`);
  lines.push(`エージェント固有の指示にしたいときは、見出しに (Claude Code 固有) か (Codex 固有) を付けると比較から外れます。`);
  block(lines);
}

// ---- stop: Stop ----

function run(cmd, args) {
  try {
    return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return "";
  }
}

function mtime(p) {
  try {
    return statSync(p).mtimeMs;
  } catch {
    return 0;
  }
}

function changedFiles(root) {
  // 追加したばかりのファイルはディレクトリ 1 行にまとめられてしまうため、--untracked-files=all で 1 件ずつ出させる。
  // 未追跡でない行は行頭が空白で始まるので、git() ではなく空白を落とさない gitLines() で受ける
  return gitLines(root, ["status", "--porcelain", "--untracked-files=all"]).map((line) => {
    const p = line.slice(3);
    // 改名は "old -> new" で出るため、今あるほうの名前を取る
    const arrow = p.lastIndexOf(" -> ");
    return unquote(arrow >= 0 ? p.slice(arrow + 4) : p);
  });
}

async function runStop(input) {
  // 同じ指摘で何度も引き止めないよう、hook 由来の継続では確認しない
  if (input.stop_hook_active) return;
  const cwd = input.cwd || process.cwd();
  const root = git(cwd, ["rev-parse", "--show-toplevel"]);
  if (!isDotfiles(root)) return;

  const changed = changedFiles(root);
  if (changed.length === 0) return;
  const lines = [];

  // sheldon の lock はリポジトリの外 (~/.local/share/sheldon) にあり git status では見えないので、更新時刻で比べる
  if (changed.includes("config/sheldon/plugins.toml")) {
    const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local/share");
    const lock = path.join(dataHome, "sheldon", "plugins.lock");
    if (mtime(lock) < mtime(path.join(root, "config/sheldon/plugins.toml"))) {
      lines.push("guard: plugins.toml を変更したあと sheldon lock を実行していません。");
    }
  }

  if (changed.includes("config/mise/config.toml") && run("mise", ["ls", "--missing"])) {
    lines.push("guard: mise の設定に未インストールのツールがあります。mise install を実行してください。");
  }

  // plugin は version を上げないと claude plugin update がキャッシュを差し替えず、変更が反映されない
  const plugins = new Set();
  for (const f of changed) {
    const m = /^agents\/plugins\/([^/]+)\//.exec(f);
    if (m) plugins.add(m[1]);
  }
  for (const name of plugins) {
    if (!changed.includes(`agents/plugins/${name}/.claude-plugin/plugin.json`)) {
      lines.push(`guard: agents/plugins/${name} を変更しましたが .claude-plugin/plugin.json の version を上げていません。`);
    }
  }

  if (lines.length > 0) block(lines);
}

// ---- entrypoint ----

try {
  const input = JSON.parse(await readStdin());
  const mode = process.argv[2];
  if (mode === "bash") await runBash(input);
  else if (mode === "sync") await runSync(input);
  else if (mode === "stop") await runStop(input);
} catch {
  // 入力の解析や git の呼び出しに失敗しても、作業は止めない
}
process.exit(0);
