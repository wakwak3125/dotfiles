# Storybook 検証

Storybook + Playwright + Figma の比較ループを回す手順。

このスクリプトは **Skill 配下にインストールされた Playwright をどのプロジェクトからも共有して使う**設計。プロジェクトごとに Playwright をインストールする必要はない。

## 目次

- Story の用意基準 (フェーズ 4d)
- 初回セットアップ (存在チェック / install 手順)
- プロジェクトの前提
- ループ実行 (1. Story ID 特定 / 2. Story リスト構築 / 3. スクショ実行 / 4. ペア存在チェック / 5. 比較)
- 反復
- 停止条件
- Claude の比較の心得
- トラブルシューティング

## Story の用意基準 (フェーズ 4d)

どの state に専用 story を用意するかはタスクごとに判断する:

- Figma の variant として異なる state → 専用 story
- 振る舞い的に DOM が変わる state (loading、error、empty) → 専用 story
- Storybook controls で十分カバーできる単なる props 順列 → スキップ

Story 名は state を反映: `Default`、`Hover`、`Focus`、`Disabled`、`Loading`、`Error`、`Empty`。

## 初回セットアップ (マシンごとに 1 回だけ)

`${CLAUDE_SKILL_DIR}` は Claude Code が当該 Skill のディレクトリを指して設定する環境変数(personal/project どちらの配置でも正しく解決される)。

### 存在チェック (常に実行)

検証フェーズに入ったらまず存在確認だけを行う。`npm install` を直接呼ぶことは禁止:

```bash
test -d "${CLAUDE_SKILL_DIR}/node_modules/playwright" \
  && test -d "${CLAUDE_SKILL_DIR}/node_modules/playwright-core" \
  && test -d "${CLAUDE_SKILL_DIR}/node_modules/pixelmatch" \
  && test -d "${CLAUDE_SKILL_DIR}/node_modules/pngjs" \
  && echo "deps ready" \
  || echo "deps NOT installed"
```

### 「ready」が出た場合

**何もしない。** 既にインストール済みなので追加の install は不要。続けてスクリプト実行へ。`npm install` を「念のため」走らせる行為は、auto-mode で権限プロンプトを発生させて停止するだけ。

### 「NOT installed」が出た場合

ユーザーに **「Playwright と Chromium をインストールしてよいか」を明示的に確認してから**、承認を得た後に以下を実行:

```bash
(cd "${CLAUDE_SKILL_DIR}" && npm install && npx playwright install chromium)
```

Chromium binary のダウンロードを伴うため (200MB+、数分)、auto-mode でも自動実行しない。

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

実行中の Storybook から `index.json` を読み、フェーズ 4d で追加/更新した story の `id` を取り出す:

```
GET http://localhost:6006/index.json
```

スクリプトは自動で `localhost:6006` / `6007` / `9009` を試して使えるものを採用するので、URL を意識する必要は通常ない。プロジェクトが特殊ポートを使う場合のみ `STORYBOOK_URL` で上書き。

### 2. Story リスト構築

対象 story ごとに、スクリプト介入が必要な state を判断:

- `Default`、`Disabled`、`Loading`、`Empty`、`Error` — 介入なし、遷移して撮るだけ
- `Hover` — story root か特定セレクタ (`hoverSelector`) を hover
- `Focus` — story 内の focusable 要素 (`focusSelector` で上書き可) を focus
- `Active` — mousedown + 保持

これを JSON で `STORIES` env var に渡す。

**ビューポートは Figma に存在する breakpoint だけを `VIEWPORTS` で明示する。** スクリプトのデフォルト (mobile + desktop) に頼らない。viewport 幅は Figma フレーム幅に合わせる — 寸法が揃っていないと 4f の機械 diff が `dimensionMismatch` を報告し、比較精度も落ちる。

### 3. スクショ実行 (任意のプロジェクトから)

プロジェクトルートで CWD を取り、絶対パスでスクリプトを呼ぶ:

```bash
cd <project-root>
STORIES='[{"id":"button--default"},{"id":"button--hover","state":"hover"}]' \
  node "${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs"
```

出力は `/tmp/dev-task-visual-check/<project-basename>/<story-id>__<state>__<viewport>__playwright.png` に保存される (`OUT_DIR` で上書き可)。`<project-basename>` は CWD のディレクトリ名。

Figma 側の画像は同じディレクトリに `<story-id>__<state>__<viewport>__figma.png` の命名で対称的に保存する (フェーズ 4e-2 を参照)。両方揃って初めて視覚比較が成立する。

特殊ポートやビューポート指定が必要な場合のみ追加:

```bash
STORYBOOK_URL=http://localhost:7777 \
VIEWPORTS='[{"name":"desktop","width":1440,"height":900}]' \
STORIES='[...]' \
  node "${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs"
```

### 4. ペア存在チェック (フェーズ 4e-3)

各 story × state × viewport について、`__playwright.png` と `__figma.png` の**両方**が存在することを確認する。揃わない限り機械 diff / 視覚比較に進まない:

```bash
DIR="/tmp/dev-task-visual-check/$(basename "$(pwd)")"
ls "$DIR"/*__playwright.png | while read pw; do
  fig="${pw%__playwright.png}__figma.png"
  [ -f "$fig" ] || echo "missing: $fig"
done
```

欠けているペアがあれば Figma 画像取得 (4e-2) に戻る。

### 5. 比較

**まず機械的 diff を生成する** (フェーズ 4f):

```bash
cd <project-root>
node "${CLAUDE_SKILL_DIR}/scripts/diff-pairs.mjs"
```

各ペアの `__diff.png` (差分ハイライト) と diff 率が出る。`dimensionMismatch` があれば取得条件のずれなので先に直す。diff 画像は「どこを注視すべきか」を絞る手がかりであり、最終判定は visual-reviewer が行う。

その上で、各 story+state+viewport の組合せについて:

- Playwright スクショを読み込む
- 対応する variant の Figma フレーム画像を同じビューポートで読み込む
- `__diff.png` でハイライトされた領域を重点的に確認する
- 以下の順で視覚比較:
  1. **構造** — 同じ要素が存在し、階層が一致
  2. **余白** — padding、gap、margin が一貫 (差分はトークン単位以内)
  3. **タイポグラフィ** — font、size、weight、line height
  4. **色** — fill、stroke、テキスト色
  5. **state 特有** — hover/focus/disabled の描画が default と期待通りに異なる

差分は story ごとに構造化リストで記録。印象で反復せず、具体的なプロパティ名で指摘する。

## 反復

指摘した差分ごとに:

- 仕様 (フェーズ 4a の出力) または token-map (フェーズ 4b) にトレースバック
- 症状ではなく原因を直す (誤ったトークン名か、誤った値か)
- 影響を受けた story だけ撮り直す (毎回全件回さない)
- `__figma.png` は初回取得をキャッシュとして流用する (Figma デザイン側が変わったときだけ再取得)
- 撮り直したペアは `diff-pairs.mjs` を再実行して `__diff.png` を更新する

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
| `Cannot find package 'pixelmatch'` | 旧構成でセットアップ済み (pixelmatch 追加前) | `cd "${CLAUDE_SKILL_DIR}" && npm install` (ユーザー確認後) |
| `browserType.launch: Executable doesn't exist` | Chromium 未ダウンロード | `cd "${CLAUDE_SKILL_DIR}" && npx playwright install chromium` |
| `Storybook を検出できませんでした` | Storybook 未起動 or 特殊ポート | プロジェクトで起動するか `STORYBOOK_URL` を設定 |
| スクショが空白/真っ白 | dev server が描画前 | `page.waitForTimeout` を上げる or `networkidle` 待ち追加 |
