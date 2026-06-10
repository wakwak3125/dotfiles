// scripts/diff-pairs.mjs
//
// dev-task Skill フェーズ 4f の機械的画像 diff。
// /tmp/dev-task-visual-check/<project-basename>/ 内の
// __playwright.png / __figma.png ペアを pixelmatch で比較し、
// 差分ハイライト画像 (__diff.png) と diff 率の JSON サマリを出力する。
//
// 任意のプロジェクトディレクトリから絶対パスで呼ぶ:
//   cd <project-root>
//   node ${CLAUDE_SKILL_DIR}/scripts/diff-pairs.mjs
//
// env var:
//   DIR        — 比較ディレクトリの上書き (既定: /tmp/dev-task-visual-check/$(basename CWD))
//   THRESHOLD  — pixelmatch の色距離閾値 (既定: 0.2。Figma とブラウザは別レンダラなので
//                アンチエイリアス耐性を持たせる)
//
// 出力 (stdout, JSON):
//   { dir, results: [{ pair, diffRatio, dimensionMismatch, diffImage } | { pair, error }] }
//
// diff 率はあくまで「どのペアをどれだけ注視すべきか」の手がかり。
// PASS / NEEDS_REVISION の判定は 4g の visual-reviewer が行う。

import pixelmatch from 'pixelmatch';
import { PNG } from 'pngjs';
import { readdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const DIR =
  process.env.DIR ??
  path.join('/tmp/dev-task-visual-check', path.basename(process.cwd()));
const THRESHOLD = Number(process.env.THRESHOLD ?? 0.2);

// 寸法が異なる画像同士を比較できるよう、大きい方の寸法に白背景でパディングする。
// 寸法不一致自体は dimensionMismatch として報告する (取得条件のずれの可能性)。
function padTo(png, width, height) {
  if (png.width === width && png.height === height) return png;
  const out = new PNG({ width, height });
  out.data.fill(255); // 白・不透明
  PNG.bitblt(png, out, 0, 0, png.width, png.height, 0, 0);
  return out;
}

let files;
try {
  files = await readdir(DIR);
} catch {
  console.error(`比較ディレクトリが存在しません: ${DIR}`);
  console.error('4e-1 (Playwright スクショ) を先に実行してください。');
  process.exit(1);
}

const playwrightFiles = files.filter((f) => f.endsWith('__playwright.png')).sort();
if (playwrightFiles.length === 0) {
  console.error(`${DIR} に __playwright.png がありません。4e-1 を先に実行してください。`);
  process.exit(1);
}

const results = [];
for (const pw of playwrightFiles) {
  const pairName = pw.replace(/__playwright\.png$/, '');
  const fig = `${pairName}__figma.png`;
  if (!files.includes(fig)) {
    results.push({ pair: pairName, error: 'figma image missing (4e-2 未完了)' });
    continue;
  }

  const a = PNG.sync.read(await readFile(path.join(DIR, pw)));
  const b = PNG.sync.read(await readFile(path.join(DIR, fig)));
  const dimensionMismatch =
    a.width !== b.width || a.height !== b.height
      ? { playwright: [a.width, a.height], figma: [b.width, b.height] }
      : null;

  const width = Math.max(a.width, b.width);
  const height = Math.max(a.height, b.height);
  const pa = padTo(a, width, height);
  const pb = padTo(b, width, height);

  const diff = new PNG({ width, height });
  const diffPixels = pixelmatch(pa.data, pb.data, diff.data, width, height, {
    threshold: THRESHOLD,
    includeAA: false, // アンチエイリアス由来のノイズを無視
  });

  const diffImage = `${pairName}__diff.png`;
  await writeFile(path.join(DIR, diffImage), PNG.sync.write(diff));

  results.push({
    pair: pairName,
    diffRatio: Number((diffPixels / (width * height)).toFixed(4)),
    dimensionMismatch,
    diffImage,
  });
}

console.log(JSON.stringify({ dir: DIR, results }, null, 2));
