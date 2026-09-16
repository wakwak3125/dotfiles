#!/usr/bin/env node
// Claude Code hook から textlint を実行する。
//   markdown: PostToolUse (Write|Edit|MultiEdit)。書き込んだ Markdown の変更箇所だけを確認する
//   comment:  PostToolUse (Write|Edit|MultiEdit)。Markdown 以外のファイルに書いたコメントの変更箇所を、言い換えの規則 (prh) だけで確認する
//   pr:       PreToolUse (Bash)。gh pr create / edit のタイトルと本文を textlint と pr-writing skill の規範で確認し、指摘があれば実行を止める
//   mcp:      PreToolUse (Linear / Notion の書き込み系 MCP ツール)。送信する文書を確認し、指摘があれば実行を止める
// ルールをこのディレクトリの node_modules から解決させるため、スクリプトもここに置く。
// hook の不具合で作業を止めないよう、解析や lint に失敗したときは常に exit 0 で通す。
import { createHash } from "node:crypto";
import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
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
// タイトルや部分更新の断片は句点で終わらないのが普通なので、このルールだけ外す
const PERIOD_RULE = "ja-technical-writing/ja-no-mixed-period";
// MCP ツールの呼び出しには TEXTLINT_SKIP=1 のような目印を付けられず、HTML コメントは Linear や Notion で表示されうる。
// そのため一度止めた内容を覚えておき、同じ内容で再実行されたら誤検知と判断したものとして通す。
// Linux の /tmp は他のユーザーと共有され、先にディレクトリを作られると記録に失敗するため、ホーム配下に置く
const BLOCKED_DIR = path.join(os.homedir(), ".cache", "claude-textlint-blocked");
// 直して送り直した後に残った古い記録で、後日の無関係な送信を通さないよう、有効期間を区切る
const BLOCKED_TTL_MS = 10 * 60 * 1000;

async function readStdin() {
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

const linters = new Map();

// config は文書の種類で変える。散文は preset-ja-technical-writing まで見るが、
// コードコメントは一文の長さや文末の規則が合わないので prh の言い換えだけを見る
async function lint(text, filename, config = ".textlintrc.json") {
  // PR と MCP の hook はツール呼び出しごとに起動するので、textlint は確認が必要になってから読み込む。
  // node_modules がないときの失敗も、ここで読み込めば末尾の catch で exit 0 にできる。
  // 項目の多い MCP 呼び出しで設定を何度も読み込まないよう、linter は設定ごとに 1 回だけ作る
  if (!linters.has(config)) {
    linters.set(
      config,
      (async () => {
        const { createLinter, loadTextlintrc } = await import("textlint");
        const descriptor = await loadTextlintrc({
          configFilePath: path.join(HERE, config),
          node_modulesDir: path.join(HERE, "node_modules"),
        });
        return createLinter({ descriptor });
      })(),
    );
  }
  const result = await (await linters.get(config)).lintText(text, filename);
  return result.messages.filter((m) => m.severity === 2);
}

function format(label, messages) {
  // no-mix-dearu-desumasu などは集計を複数行で出すため、1 行目だけ使う
  return messages.map((m) => `- ${label}:${m.line}:${m.column} ${m.message.split("\n")[0]} (${m.ruleId})`);
}

// targets: { label, text, fragment } の配列。fragment はタイトルや部分更新の断片を表す
async function lintTargets(targets) {
  const lines = [];
  for (const { label, text, fragment } of targets) {
    if (typeof text !== "string" || !text.trim()) continue;
    // タイトルも見出し (# ...) ではなく段落として渡す。見出し扱いだと助詞の重複なども対象外になるため
    const messages = (await lint(`${text}\n`, `${label}.md`)).filter((m) => !fragment || m.ruleId !== PERIOD_RULE);
    lines.push(...format(label, messages));
  }
  return lines;
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

// 行コメントの記号。ここにも BLOCK_COMMENT にも無い種類のファイルは確認しない
const LINE_COMMENT = {
  c: ["//"], cc: ["//"], cpp: ["//"], cs: ["//"], h: ["//"], hpp: ["//"],
  cjs: ["//"], dart: ["//"], go: ["//"], java: ["//"], js: ["//"], jsx: ["//"],
  kt: ["//"], kts: ["//"], mjs: ["//"], rs: ["//"], scala: ["//"], swift: ["//"], ts: ["//"], tsx: ["//"],
  php: ["//", "#"],
  bash: ["#"], nix: ["#"], py: ["#"], rb: ["#"], sh: ["#"], tf: ["#"], toml: ["#"], yaml: ["#"], yml: ["#"], zsh: ["#"],
  hs: ["--"], lua: ["--"], sql: ["--"],
  clj: [";"], el: [";"], lisp: [";"],
};
// 拡張子を持たない設定ファイルとスクリプト
const LINE_COMMENT_BY_NAME = {
  ".zshrc": ["#"], ".zshenv": ["#"], ".zprofile": ["#"], ".gitignore": ["#"],
  zshenv: ["#"], gitconfig: ["#"], Makefile: ["#"], Dockerfile: ["#"],
};
// /* ... */ を解釈する種類
const BLOCK_COMMENT = new Set([
  "c", "cc", "cpp", "cs", "h", "hpp", "cjs", "css", "dart", "go", "java", "js", "jsx",
  "kt", "kts", "mjs", "php", "rs", "scala", "scss", "swift", "ts", "tsx",
]);
const HAS_JAPANESE = /[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]/;

function commentSyntax(filePath) {
  const base = path.basename(filePath);
  const ext = path.extname(base).slice(1).toLowerCase();
  const markers = LINE_COMMENT[ext] ?? LINE_COMMENT_BY_NAME[base];
  const block = BLOCK_COMMENT.has(ext);
  return markers || block ? { markers: markers ?? [], block } : null;
}

// コメント以外を空白で潰す。行数と桁が変わらないので、textlint の指摘位置がそのまま元のファイルの位置になる。
// 文字列リテラルの中までは見分けないため、"//" を含む文字列をコメントと取り違えることがある
function maskToComments(content, { markers, block }) {
  const out = [];
  let inBlock = false;
  for (const line of content.split("\n")) {
    let masked = "";
    let i = 0;
    while (i < line.length) {
      if (inBlock) {
        const end = line.indexOf("*/", i);
        if (end === -1) {
          masked += line.slice(i);
          break;
        }
        masked += `${line.slice(i, end)}  `;
        i = end + 2;
        inBlock = false;
        continue;
      }
      const starts = [];
      if (block) {
        const at = line.indexOf("/*", i);
        if (at !== -1) starts.push([at, "/*"]);
      }
      for (const marker of markers) {
        let at = line.indexOf(marker, i);
        // https:// の // をコメントの始まりと取り違えないようにする
        while (at > 0 && marker === "//" && line[at - 1] === ":") at = line.indexOf(marker, at + 2);
        if (at !== -1) starts.push([at, marker]);
      }
      if (starts.length === 0) {
        masked += " ".repeat(line.length - i);
        break;
      }
      starts.sort((a, b) => a[0] - b[0]);
      const [at, kind] = starts[0];
      // コメントの記号自体も空白にする。残すと Markdown の見出しや強調として解釈されてしまう
      masked += " ".repeat(at - i + kind.length);
      if (kind === "/*") {
        i = at + 2;
        inBlock = true;
      } else {
        masked += line.slice(at + kind.length);
        break;
      }
    }
    out.push(masked);
  }
  return out.join("\n");
}

// CLAUDE.md の「定訳のある一般語は日本語で書く」を、Markdown 以外のファイルのコメントにも当てる
async function lintComment(input) {
  const filePath = input.tool_input?.file_path;
  if (!filePath || /\.(md|markdown)$/i.test(filePath)) return;
  const rel = path.relative(input.cwd ?? process.cwd(), filePath);
  if (rel.startsWith("..") || path.isAbsolute(rel)) return;
  const syntax = commentSyntax(filePath);
  if (!syntax) return;

  const content = await readFile(filePath, "utf8");
  const ranges = changedLineRanges(content, input);
  if (ranges && ranges.length === 0) return;

  const masked = maskToComments(content, syntax);
  if (!HAS_JAPANESE.test(masked)) return;

  // textlint は拡張子でプロセッサを選ぶので、潰したあとのテキストは Markdown として渡す
  const messages = (await lint(masked, `${rel}.md`, ".textlintrc.comment.json")).filter(
    (m) => !ranges || ranges.some(([s, e]) => m.line >= s && m.line <= e),
  );
  if (messages.length === 0) return;
  report(
    `textlint: ${rel} のコメントに ${messages.length} 件の指摘があります。誤検知でなければ修正してください。`,
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

// pr-writing skill の規範のうち、文面の意味を読まずに判定できるものだけを確認する
const PR_TITLE_MAX = 60;
const PR_BODY_MAX_LINES = 10;
const PR_TICKET_AT_HEAD = /^(?:\w+(?:\([^)]*\))?!?:\s*)?\[?[A-Z][A-Z0-9]+-\d+\b/;
const PR_BANNED_PHRASES = [
  /と考えられます/,
  /が期待されます/,
  /かと思います/,
  /いたしました/,
  /ご確認のほど/,
  /本\s*PR\s*では/,
  /以上が変更内容/,
  /まとめると/,
  /既存機能への影響はありません/,
  /^\s*(?:[-*]\s*)?(?:N\/A|特になし)\s*$/m,
];

function prNormLines(title, body) {
  const lines = [];
  if (title) {
    const length = [...title].length;
    if (length > PR_TITLE_MAX) lines.push(`- title: ${length} 字あり、上限の ${PR_TITLE_MAX} 字を超えている (pr-writing)`);
    if (PR_TICKET_AT_HEAD.test(title)) lines.push("- title: チケット番号は先頭ではなく末尾か本文に置く (pr-writing)");
  }
  if (body) {
    // 見出し、空行、Claude Code の attribution とセッション URL は分量に数えない
    const counted = body
      .split("\n")
      .filter(
        (l) =>
          l.trim() &&
          !/^#{1,6}\s/.test(l) &&
          !l.includes("Generated with [Claude Code]") &&
          !/^https:\/\/claude\.ai\/code\/session_\S+$/.test(l.trim()),
      );
    if (counted.length > PR_BODY_MAX_LINES) {
      lines.push(`- body: 本文が ${counted.length} 行あり、上限の ${PR_BODY_MAX_LINES} 行を超えている (pr-writing)`);
    }
    for (const phrase of PR_BANNED_PHRASES) {
      const found = phrase.exec(body);
      if (found) lines.push(`- body: 「${found[0].trim()}」は情報を増やさないので使わない (pr-writing)`);
    }
  }
  return lines;
}

async function lintPr(input) {
  const command = input.tool_input?.command;
  if (!command || SKIP_MARKER.test(command)) return;
  const gh = GH_PR.exec(command);
  if (!gh) return;

  const { title, body } = await extractPr(command, command.slice(gh.index), input.cwd ?? process.cwd());
  const lines = [
    ...prNormLines(title, body),
    ...(await lintTargets([
      { label: "title", text: title, fragment: true },
      { label: "body", text: body },
    ])),
  ];
  if (lines.length === 0) return;
  report(
    `textlint: PR のタイトルと本文に ${lines.length} 件の指摘があるため gh の実行を止めました。修正して再実行してください。` +
      "規範の指摘 (pr-writing) は pr-writing skill を読んで直してください。" +
      "誤検知なら本文の該当箇所を <!-- textlint-disable rule名 --> と <!-- textlint-enable --> で囲むか、" +
      "コマンドに TEXTLINT_SKIP=1 を付けて再実行してください。",
    lines,
  );
}

// Linear の patch は op によって本文を new_string か text に持つ
function linearPatchTargets(patch) {
  return (patch ?? []).map((p, n) => ({ label: `patch[${n}]`, text: p.new_string ?? p.text, fragment: true }));
}

// ツール名の末尾 (mcp__<server>__<tool> の <tool>) ごとに、送信する文書の項目を取り出す。
// ツールを増やしたら bootstrap.sh の mcp_matcher にも加える (hook はそこに一致したツールでしか起動しない)。
// データベース配下の Notion ページはタイトルのプロパティ名が Name などになるため、そのタイトルは確認できない
const MCP_TARGETS = {
  save_issue: (i) => [
    { label: "title", text: i.title, fragment: true },
    { label: "description", text: i.description },
    ...linearPatchTargets(i.patch),
  ],
  save_document: (i) => [
    { label: "title", text: i.title, fragment: true },
    { label: "content", text: i.content },
    ...linearPatchTargets(i.patch),
  ],
  save_comment: (i) => [{ label: "body", text: i.body }],
  "notion-create-pages": (i) =>
    (i.pages ?? []).flatMap((p, n) => [
      { label: `pages[${n}].title`, text: p.properties?.title, fragment: true },
      { label: `pages[${n}].content`, text: p.content },
    ]),
  "notion-update-page": (i) => [
    { label: "title", text: i.properties?.title, fragment: true },
    { label: "content", text: i.content },
    { label: "new_str", text: i.new_str },
    ...(i.content_updates ?? []).map((u, n) => ({ label: `content_updates[${n}]`, text: u.new_str, fragment: true })),
  ],
  "notion-create-comment": (i) => [{ label: "markdown", text: i.markdown }],
};

async function lintMcp(input) {
  const tool = input.tool_name?.split("__").pop();
  const extract = MCP_TARGETS[tool];
  if (!extract) return;

  const lines = await lintTargets(extract(input.tool_input ?? {}));
  if (lines.length === 0) return;

  // 同じ文面を別の課題やページへ送るときに逃げ道を使えないよう、送り先の id を含む入力全体で判定する
  const key = createHash("sha256")
    .update(JSON.stringify([input.tool_name, input.tool_input]))
    .digest("hex");
  if (await consumeBlocked(key)) return;
  try {
    await mkdir(BLOCKED_DIR, { recursive: true });
    await writeFile(path.join(BLOCKED_DIR, key), "");
  } catch {
    // 記録に失敗しても指摘は返す。末尾の catch に任せると、指摘があるのに送信が通ってしまう
  }
  report(
    `textlint: ${tool} で送信する文書に ${lines.length} 件の指摘があるため実行を止めました。修正して再実行してください。` +
      "誤検知と判断した場合は、同じ内容のまま再実行すれば一度だけ通します。",
    lines,
  );
}

// 有効期間内の記録があれば消費して true を返す。期限切れの記録は消すだけで通さない
async function consumeBlocked(key) {
  const marker = path.join(BLOCKED_DIR, key);
  const stats = await stat(marker).catch(() => null);
  if (!stats) return false;
  await rm(marker, { force: true });
  return Date.now() - stats.mtimeMs < BLOCKED_TTL_MS;
}

const handlers = { markdown: lintMarkdown, comment: lintComment, pr: lintPr, mcp: lintMcp };

try {
  const handler = handlers[process.argv[2]];
  if (handler) await handler(JSON.parse(await readStdin()));
} catch (error) {
  process.stderr.write(`textlint hook: ${error.message}\n`);
}
process.exit(0);
