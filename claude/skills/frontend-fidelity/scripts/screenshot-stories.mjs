// scripts/screenshot-stories.mjs
//
// frontend-fidelity Skill の検証スクリプト。Skill 配下の node_modules から
// playwright を解決するため、初回のみ ${CLAUDE_SKILL_DIR} 直下で
// `npm install && npx playwright install chromium` を実行しておくこと。
//
// 任意のプロジェクトディレクトリから絶対パスで呼ぶ:
//   cd <project-root>
//   STORIES='[{"id":"button--default"},{"id":"button--hover","state":"hover"}]' \
//     node ${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs
//
// 出力は CWD 配下の ./visual-check に保存される。
//
// story オブジェクトの形:
//   { id: string, state?: 'default' | 'hover' | 'focus' | 'active', focusSelector?: string }

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

async function detectStorybook() {
  for (const url of STORYBOOK_CANDIDATES) {
    try {
      const res = await fetch(`${url}/index.json`, { signal: AbortSignal.timeout(2000) });
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

const OUT_DIR = process.env.OUT_DIR ?? path.join(process.cwd(), 'visual-check');

const VIEWPORTS = process.env.VIEWPORTS
  ? JSON.parse(process.env.VIEWPORTS)
  : [
      { name: 'mobile', width: 390, height: 844 },
      { name: 'desktop', width: 1280, height: 800 },
    ];

const stories = JSON.parse(process.env.STORIES ?? '[]');

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
        deviceScaleFactor: 2,
      });
      const page = await ctx.newPage();

      const url = `${STORYBOOK_URL}/iframe.html?id=${story.id}&viewMode=story`;
      await page.goto(url, { waitUntil: 'networkidle' });
      await page.waitForTimeout(150); // paint 安定待ち

      const root = page.locator('#storybook-root, #root').first();
      await root.waitFor({ state: 'visible' });

      const state = story.state ?? 'default';

      if (state === 'hover') {
        await root.hover();
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

      const fileName = `${story.id}__${state}__${vp.name}.png`;
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
