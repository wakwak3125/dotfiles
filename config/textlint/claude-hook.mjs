#!/usr/bin/env node
// Claude Code hook から textlint を実行する。
//   markdown: PostToolUse (Write|Edit|MultiEdit)。書き込んだ Markdown の変更箇所だけを確認する
//   pr:       PreToolUse (Bash)。gh pr create / edit のタイトルと本文を確認し、指摘があれば実行を止める
// ルールをこのディレクトリの node_modules から解決させるため、スクリプトもここに置く。
// hook の不具合で作業を止めないよう、解析や lint に失敗したときは常に exit 0 で通す。
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
// 指摘をそのまま会話に積むとトークンを圧迫するため、件数を絞る
const MAX_REPORTS = 10;
// PR の hook で誤検知が続いたときの逃げ道。コマンドに含めると確認を飛ばす
const SKIP_MARKER = /\bTEXTLINT_SKIP=1\b/;
// 行頭か区切り記号の直後に限る。コミットメッセージの中に書いた「gh pr create」で止めないため
const GH_PR = /(?:^|[;&|(\n])\s*(?:\w+=\S*\s+)*gh\s+pr\s+(?:create|edit)\b/;
const QUOTED = String.raw`"(?:[^"\\]|\\.)*"|'[^']*'`;

async function readStdin() {
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

async function lint(text, filename) {
  // PR の hook は Bash の呼び出しごとに起動するので、textlint は確認が必要になってから読み込む。
  // node_modules がないときの失敗も、ここで読み込めば末尾の catch で exit 0 にできる
  const { createLinter, loadTextlintrc } = await import("textlint");
  const descriptor = await loadTextlintrc({
    configFilePath: path.join(HERE, ".textlintrc.json"),
    node_modulesDir: path.join(HERE, "node_modules"),
  });
  const result = await createLinter({ descriptor }).lintText(text, filename);
  return result.messages.filter((m) => m.severity === 2);
}

function format(label, messages) {
  // no-mix-dearu-desumasu などは集計を複数行で出すため、1 行目だけ使う
  return messages.map((m) => `- ${label}:${m.line}:${m.column} ${m.message.split("\n")[0]} (${m.ruleId})`);
}

function report(header, lines) {
  const shown = lines.slice(0, MAX_REPORTS);
  const rest = lines.length - shown.length;
  const out = [header, ...shown];
  if (rest > 0) out.push(`- ほか ${rest} 件`);
  process.stderr.write(`${out.join("\n")}\n`);
  process.exit(2);
}

// Edit 前から残っている指摘まで返すと無関係な修正を誘発するため、new_string を含む行 (1 始まりの区間) に絞る。
// Write は null を返してファイル全体を対象にする。
// 指摘は開始行で判定するので、複数行の段落の末尾だけを変えたときの sentence-length などは拾えない
function changedLineRanges(content, input) {
  if (input.tool_name === "Write") return null;
  const snippets =
    input.tool_name === "MultiEdit"
      ? (input.tool_input.edits ?? []).map((e) => e.new_string)
      : [input.tool_input.new_string];
  const ranges = [];
  for (const snippet of snippets) {
    // 前後の改行まで数えると、変更していない隣の行が区間に入る
    const core = snippet?.replace(/^\n+|\n+$/g, "");
    if (!core) continue;
    const lineCount = core.split("\n").length;
    let from = content.indexOf(core);
    while (from !== -1) {
      const start = content.slice(0, from).split("\n").length;
      ranges.push([start, start + lineCount - 1]);
      from = content.indexOf(core, from + core.length);
    }
  }
  return ranges;
}

async function lintMarkdown(input) {
  const filePath = input.tool_input?.file_path;
  if (!filePath || !/\.(md|markdown)$/i.test(filePath)) return;
  // memory や scratchpad など作業ディレクトリ外の Markdown は対象にしない
  const rel = path.relative(input.cwd ?? process.cwd(), filePath);
  if (rel.startsWith("..") || path.isAbsolute(rel)) return;

  const content = await readFile(filePath, "utf8");
  const ranges = changedLineRanges(content, input);
  if (ranges && ranges.length === 0) return;

  const messages = (await lint(content, filePath)).filter(
    (m) => !ranges || ranges.some(([s, e]) => m.line >= s && m.line <= e),
  );
  if (messages.length === 0) return;
  report(
    `textlint: ${rel} の変更箇所に ${messages.length} 件の指摘があります。誤検知でなければ修正してください。`,
    format(rel, messages),
  );
}

function unquote(raw) {
  if (raw.startsWith("'")) return raw.slice(1, -1);
  if (raw.startsWith('"')) return raw.slice(1, -1).replace(/\\(["\\$`])/g, "$1");
  return raw;
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// PreToolUse はコマンドの実行前に動くため、同じコマンドで書き出す本文ファイルはまだ古い内容のままになる。
// cat > file <<EOF で書き出すならその heredoc を本文とみなし、それ以外の方法で書き出すなら確認しない
async function readBodyFile(command, file, cwd) {
  const target = escapeRegExp(file);
  const written = new RegExp(
    String.raw`\bcat\s*>\s*["']?${target}["']?\s*<<-?\s*['"]?(\w+)['"]?[^\n]*\n([\s\S]*?)\n\s*\1(?:\n|$)`,
  ).exec(command);
  if (written) return written[2];
  if (new RegExp(String.raw`(?:>|\btee\s+(?:-a\s+)?)\s*["']?${target}(?:["'\s;&|)]|$)`).test(command)) return undefined;
  return readFile(path.resolve(cwd, file), "utf8");
}

// gh の引数を完全に解釈するのは無理なので、Claude が実際に使う形だけを拾う:
//   --body "$(cat <<'EOF' ... EOF)" / --body-file <path> / --title "..." / --body "..."
// 本文に含まれる "-t" などをタイトル引数と誤認しないよう、本文として拾った部分は以降の検索対象から除く
async function extractPr(command, args, cwd) {
  const parts = {};
  let rest = args;

  const heredoc = /(?:--body|-b)(?:=|\s+)"?\$\(cat\s+<<-?\s*['"]?(\w+)['"]?[^\n]*\n([\s\S]*?)\n\s*\1\s*\)"?/.exec(rest);
  if (heredoc) {
    parts.body = heredoc[2];
    rest = rest.replace(heredoc[0], "");
  }

  if (parts.body === undefined) {
    const bodyFile = new RegExp(String.raw`(?:--body-file|-F)(?:=|\s+)(${QUOTED}|[^\s;&|]+)`).exec(rest);
    if (bodyFile) {
      const file = unquote(bodyFile[1]);
      if (file !== "-") parts.body = await readBodyFile(command, file, cwd);
    }
  }

  if (parts.body === undefined) {
    const body = new RegExp(String.raw`(?:--body|-b)(?:=|\s+)(${QUOTED})`).exec(rest);
    // "$(...)" のような展開を含む本文は実際の値がわからないので確認しない
    if (body && !body[1].includes("$(")) {
      parts.body = unquote(body[1]);
      rest = rest.replace(body[0], "");
    }
  }

  const title = new RegExp(String.raw`(?:--title|-t)(?:=|\s+)(${QUOTED})`).exec(rest);
  if (title && !title[1].includes("$(")) parts.title = unquote(title[1]);

  return parts;
}

async function lintPr(input) {
  const command = input.tool_input?.command;
  if (!command || SKIP_MARKER.test(command)) return;
  const gh = GH_PR.exec(command);
  if (!gh) return;

  const { title, body } = await extractPr(command, command.slice(gh.index), input.cwd ?? process.cwd());
  const lines = [];
  if (title) {
    // 見出しとして渡すと助詞の重複なども対象外になるため、段落として確認して句点の指摘だけを除く
    const messages = (await lint(`${title}\n`, "title.md")).filter(
      (m) => m.ruleId !== "ja-technical-writing/ja-no-mixed-period",
    );
    lines.push(...format("title", messages));
  }
  if (body) lines.push(...format("body", await lint(body, "body.md")));
  if (lines.length === 0) return;
  report(
    `textlint: PR のタイトルと本文に ${lines.length} 件の指摘があるため gh の実行を止めました。修正して再実行してください。` +
      "誤検知なら本文の該当箇所を <!-- textlint-disable rule名 --> と <!-- textlint-enable --> で囲むか、" +
      "コマンドに TEXTLINT_SKIP=1 を付けて再実行してください。",
    lines,
  );
}

const handlers = { markdown: lintMarkdown, pr: lintPr };

try {
  const handler = handlers[process.argv[2]];
  if (handler) await handler(JSON.parse(await readStdin()));
} catch (error) {
  process.stderr.write(`textlint hook: ${error.message}\n`);
}
process.exit(0);
