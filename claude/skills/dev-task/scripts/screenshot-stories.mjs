// scripts/screenshot-stories.mjs
//
// dev-task Skill の検証スクリプト。Skill 配下の node_modules から
// playwright を解決するため、初回のみ ${CLAUDE_SKILL_DIR} 直下で
// `npm install && npx playwright install chromium` を実行しておくこと。
//
// 任意のプロジェクトディレクトリから絶対パスで呼ぶ:
//   cd <project-root>
//   STORIES='[{"id":"button--default"},{"id":"button--hover","state":"hover"}]' \
//     node ${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs
//
// 出力は /tmp/dev-task-visual-check/<project-basename>/ に保存される。
// ファイル名規約: <story-id>__<state>__<viewport>__playwright.png
// (Figma 側は __figma.png、同じ命名で対称になる)
//
// story オブジェクトの形:
//   { id: string, state?: 'default' | 'hover' | 'focus' | 'active',
//     hoverSelector?: string, focusSelector?: string }
//
// 撮影品質の担保:
//   - document.fonts.ready を待つ (font swap 前のスクショによるタイポグラフィ誤判定を防ぐ)
//   - animation / transition を CSS で無効化 (遷移途中のスクショを防ぐ。hover 等の
//     最終スタイルは transition なしで即時適用されるため、state 比較には影響しない)

import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';

// Storybook URL の自動検出: STORYBOOK_URL 指定があれば優先、なければ
// 一般的なポートを順に試して /index.json が返るものを採用。
const STORYBOOK_CANDIDATES = process.env.STORYBOOK_URL
  ? [process.env.STORYBOOK_URL]
  : [
      'http://localhost:6006', // Storybook デフォルト
      'http://localhost:6007',
      'http://localhost:9009', // 旧デフォルト
    ];

// ローカルの Storybook は通常数十 ms で応答する。2s あれば起動済みかの
// 判定には十分で、未起動ポートで長く待たない。
const DETECT_TIMEOUT_MS = 2000;

async function detectStorybook() {
  for (const url of STORYBOOK_CANDIDATES) {
    try {
      const res = await fetch(`${url}/index.json`, { signal: AbortSignal.timeout(DETECT_TIMEOUT_MS) });
      if (res.ok) return url;
    } catch {
      // continue to next candidate
    }
  }
  throw new Error(
    `Storybook を検出できませんでした。試行: ${STORYBOOK_CANDIDATES.join(', ')}\n` +
    `Storybook が起動済みか、STORYBOOK_URL を設定してください。`
  );
}

const OUT_DIR =
  process.env.OUT_DIR ??
  path.join('/tmp/dev-task-visual-check', path.basename(process.cwd()));

// env var の JSON を、失敗時に修正方法がわかるエラー付きでパースする
function parseJsonEnv(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.error(`${name} の JSON パースに失敗しました: ${err.message}`);
    console.error(`受け取った値: ${raw}`);
    console.error(`例: ${name}='[{"id":"button--default"}]' node ...`);
    process.exit(1);
  }
}

const VIEWPORTS = parseJsonEnv('VIEWPORTS', [
  { name: 'mobile', width: 390, height: 844 },
  { name: 'desktop', width: 1280, height: 800 },
]);

const stories = parseJsonEnv('STORIES', []);

if (stories.length === 0) {
  console.error('story が指定されていません。STORIES env var を JSON 配列で渡してください。');
  console.error('例: STORIES=\'[{"id":"button--default"}]\' node ...');
  process.exit(1);
}

const STORYBOOK_URL = await detectStorybook();
console.log(`Storybook 検出: ${STORYBOOK_URL}`);
console.log(`出力先: ${OUT_DIR}`);

const browser = await chromium.launch();

try {
  for (const story of stories) {
    for (const vp of VIEWPORTS) {
      const ctx = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        deviceScaleFactor: 2, // Figma 画像と同じ 2x rendering で視覚比較するため (SKILL.md 4e-2 の解像度ルールと対応)
      });
      const page = await ctx.newPage();

      const url = `${STORYBOOK_URL}/iframe.html?id=${story.id}&viewMode=story`;
      await page.goto(url, { waitUntil: 'networkidle' });

      // アニメーション・遷移を止め、カーソル点滅も消して撮影を安定させる
      await page.addStyleTag({
        content:
          '*, *::before, *::after { animation: none !important; transition: none !important; caret-color: transparent !important; }',
      });
      // Web フォントのロード完了を待つ (font swap 前に撮ると weight / metrics が変わる)
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(150); // paint 安定待ち

      const root = page.locator('#storybook-root, #root').first();
      await root.waitFor({ state: 'visible' });

      const state = story.state ?? 'default';

      if (state === 'hover') {
        const target = story.hoverSelector
          ? root.locator(story.hoverSelector).first()
          : root;
        await target.hover();
      } else if (state === 'focus') {
        const focusable = story.focusSelector
          ? root.locator(story.focusSelector).first()
          : root.locator('button, a, input, select, textarea, [tabindex]').first();
        await focusable.focus();
      } else if (state === 'active') {
        const box = await root.boundingBox();
        if (box) {
          await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
          await page.mouse.down();
        }
      }

      await page.waitForTimeout(150); // インタラクション後のスタイル安定待ち

      const fileName = `${story.id}__${state}__${vp.name}__playwright.png`;
      const outPath = path.join(OUT_DIR, fileName);
      await mkdir(path.dirname(outPath), { recursive: true });
      await root.screenshot({ path: outPath });

      console.log(`captured: ${outPath}`);

      if (state === 'active') {
        await page.mouse.up();
      }

      await ctx.close();
    }
  }
} finally {
  await browser.close();
}
