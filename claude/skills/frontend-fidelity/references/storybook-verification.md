# Storybook 検証

Storybook + Playwright + Figma の比較ループを回す手順。

このスクリプトは **Skill 配下にインストールされた Playwright をどのプロジェクトからも共有して使う**設計。プロジェクトごとに Playwright をインストールする必要はない。

## 初回セットアップ (マシンごとに 1 回だけ)

`${CLAUDE_SKILL_DIR}` は Claude Code が当該 Skill のディレクトリを指して設定する環境変数(personal/project どちらの配置でも正しく解決される)。Claude が以下を実行する:

```bash
# まだ node_modules が無ければインストール
if [ ! -d "${CLAUDE_SKILL_DIR}/node_modules/playwright" ]; then
  (cd "${CLAUDE_SKILL_DIR}" && npm install && npx playwright install chromium)
fi
```

このチェックは毎回回しても安いので、検証フェーズに入ったタイミングで実行してよい。

## プロジェクトの前提

- Storybook 7+ が設定されている(`index.json` エンドポイントを使う)
- React + TypeScript プロジェクト

Storybook 起動だけはプロジェクトに用意があるはず:

```bash
npm run storybook -- --ci --quiet &
```

`--ci` でブラウザ自動起動を抑止、`--quiet` でログを減らす。dev server の準備完了を待ってからスクショ実行。

## ループ実行

### 1. Story ID の特定

実行中の Storybook から `index.json` を読み、フェーズ 6 で追加/更新した story の `id` を取り出す:

```
GET http://localhost:6006/index.json
```

スクリプトは自動で `localhost:6006` / `6007` / `9009` を試して使えるものを採用するので、URL を意識する必要は通常ない。プロジェクトが特殊ポートを使う場合のみ `STORYBOOK_URL` で上書き。

### 2. Story リスト構築

対象 story ごとに、スクリプト介入が必要な state を判断:

- `Default`、`Disabled`、`Loading`、`Empty`、`Error` — 介入なし、遷移して撮るだけ
- `Hover` — story root か特定セレクタを hover
- `Focus` — story 内の focusable 要素を focus
- `Active` — mousedown + 保持

これを JSON で `STORIES` env var に渡す。

### 3. スクショ実行 (任意のプロジェクトから)

プロジェクトルートで CWD を取り、絶対パスでスクリプトを呼ぶ:

```bash
cd <project-root>
STORIES='[{"id":"button--default"},{"id":"button--hover","state":"hover"}]' \
  node "${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs"
```

出力は `<project-root>/visual-check/<story-id>__<state>__<viewport>.png` に保存される (`OUT_DIR` で上書き可)。

特殊ポートやビューポート指定が必要な場合のみ追加:

```bash
STORYBOOK_URL=http://localhost:7777 \
VIEWPORTS='[{"name":"desktop","width":1440,"height":900}]' \
STORIES='[...]' \
  node "${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs"
```

### 4. 比較

各 story+state+viewport の組合せについて:

- Playwright スクショを読み込む
- 対応する variant の Figma フレーム画像を同じビューポートで読み込む
- 以下の順で視覚比較:
  1. **構造** — 同じ要素が存在し、階層が一致
  2. **余白** — padding、gap、margin が一貫 (差分はトークン単位以内)
  3. **タイポグラフィ** — font、size、weight、line height
  4. **色** — fill、stroke、テキスト色
  5. **state 特有** — hover/focus/disabled の描画が default と期待通りに異なる

差分は story ごとに構造化リストで記録。印象で反復せず、具体的なプロパティ名で指摘する。

## 反復

指摘した差分ごとに:

- 仕様 (フェーズ 4 の出力) または token-map (フェーズ 2) にトレースバック
- 症状ではなく原因を直す (誤ったトークン名か、誤った値か)
- 影響を受けた story だけ撮り直す (毎回全件回さない)

## 停止条件

- **収束。** トークン単位を超える差分が残らない → side-by-side をユーザーに見せて最終確認。
- **空回り。** 同じ差分について 3 回反復しても収束しない → 現状のスクショ、何が一致しないかの説明、仕様/トークン調整 or 差分容認の判断をユーザーに仰ぐ。
- **環境問題。** Storybook が起動しない、`node_modules` が壊れている、MCP がエラー、Chromium 未インストール → 修正(必要なら `npm install` 再実行)するか報告。コードを目視するだけのフォールバックはしない。

## Claude の比較の心得

画像を比較する際:

- 両画像の同じ領域をフル解像度で見る。サムネ比較はしない。
- 余白の差分は明らかな軸でピクセル数を数え、トークン単位に換算 (例: `1 トークン = 4px`)。
- 色の差分は CSS の問題より先にトークン取り違えを疑う (`text.primary` であるべきなのに `gray.900` を使っているなど)。
- タイポグラフィでは weight と line-height が静かに違うことが最も多い。

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `Cannot find package 'playwright'` | 初回セットアップ未実施 | `cd "${CLAUDE_SKILL_DIR}" && npm install` |
| `browserType.launch: Executable doesn't exist` | Chromium 未ダウンロード | `cd "${CLAUDE_SKILL_DIR}" && npx playwright install chromium` |
| `Storybook を検出できませんでした` | Storybook 未起動 or 特殊ポート | プロジェクトで起動するか `STORYBOOK_URL` を設定 |
| スクショが空白/真っ白 | dev server が描画前 | `page.waitForTimeout` を上げる or `networkidle` 待ち追加 |
