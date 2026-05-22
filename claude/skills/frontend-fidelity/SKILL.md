---
name: frontend-fidelity
description: React TypeScript の UI コンポーネントを、Figma デザインに最大限忠実に実装する。Figma MCP で仕様を抽出し、Storybook + Playwright で検証ループを回す。「このデザインを実装して」「Figma から作って」「モックアップ通りに」「ピクセルパーフェクトに」「このコンポーネント作って」など、デザインへの視覚的忠実度が問われるタスクで使う。`dev-task` が UI 作業を検出して委譲してきた場合にも使う。Figma、デザイン実装、Storybook story 作成、コンポーネントの視覚レビューなどに言及があれば発火。
---

# frontend-fidelity

Figma デザインを忠実に再現する React TypeScript コンポーネント実装 Skill。デザインシステムの primitive を合成し、デザイントークン (マジックナンバー禁止) を使い、Storybook + Playwright で視覚検証ループを閉じる。

**検証用の Playwright は Skill 配下にインストールされ、複数プロジェクトで共有される。**プロジェクトごとに Playwright をセットアップする必要はない (初回のみマシン単位で 1 回)。

## 呼び出し元

起動経路は 2 系統:

- **ユーザー直接** — Figma URL や story 名を会話から取り、フェーズ 1 から通常通り進める
- **`dev-task` Skill 経由** — dev-task が UI 実装を検出し、入力解決・コンテキスト収集を済ませた上で委譲してくる

### dev-task 経由のときの挙動

呼び出し時の `args` または直前メッセージに以下が含まれている前提で動く:

- 意図 / 受け入れ条件 / 仮定 / Figma ソース / 対象 story / 類似実装 / スコープ外

これらが渡されていれば、**フェーズ 1 (ソース確定) と フェーズ 3 (デザインシステム棚卸し) の探索は dev-task の成果を流用して短縮する**。Figma ソースが "未指定" の場合のみ、ユーザーに URL/ノード ID を要求する。

**フェーズ 8 の視覚チェック反復が収束したら、ユーザー最終確認を行わずに dev-task に制御を返す**。順序は「視覚反復 → (dev-task) 型/ビルド/lint → ユーザー最終確認」。型エラーで実装が修正されたら dev-task から再度 frontend-fidelity が起動され、視覚チェック反復から再開する。frontend-fidelity 側で `tsc` / `lint` を回す必要はない (視覚検証に集中する)。

## ワークフロー

1. **ソース確定** — Figma フレームと対象 Storybook story を特定する
2. **token-map 構築/更新** — Figma 変数とコード側トークンを照合する
3. **デザインシステム棚卸し** — 新規実装の前に既存 primitive を列挙する
4. **仕様抽出** — 構造、トークン、states、a11y、レスポンシブ挙動
5. **実装** — primitive を合成し、隣接ファイルを模倣
6. **Story 追加** — 検証対象の states を網羅
7. **検証** — Playwright スクショ vs Figma フレーム画像を Claude が視覚比較
8. **収束** — 構造チェック → 視覚チェック → ユーザー最終確認

## フェーズ 1: ソース確定

- **Figma**: フレーム URL またはノード ID を取得し、Figma MCP で解決可能か確認。ユーザーが画像しか貼っていない場合、トークン抽出に live source が必要なのでリンクを要求する。
- **対象 story**: 拡張対象の既存コンポーネント (優先)、またはプロジェクトの stories 慣習に従った新規パス。`*.stories.{ts,tsx}` をまず検索して関連 story を確認。

## フェーズ 2: token-map

詳細手順は `references/token-map-inference.md`。

要約: プロジェクトのトークン定義ファイル (`theme.{ts,js}`、`tokens.{ts,json}`、`tailwind.config.*`、CSS/SCSS の `:root { --... }` ブロック) を特定し、`name → value` テーブルにパース。Figma MCP で variables を取得し、値ベースで突き合わせ(名前類似度をタイブレーカに)、`/tmp/token-map.json` にセッション保存。トークン定義に変更があれば再構築。

突合不能が 30% を超える場合は、ユーザーにトークン対応 config のパスを尋ねてから続行する。

## フェーズ 3: デザインシステム棚卸し

詳細は `references/design-system-discovery.md`。

**制約: 既存 primitive で合成可能なら、新しい低レベルコンポーネントを書かない。** 候補 primitive (`src/components`、`src/ui`、`packages/*/ui`、Storybook stories) を列挙し、合成案を提示してから実装に入る。

合成不能なら、その理由を明示してから新規 primitive 実装に着手。

## フェーズ 4: 仕様抽出

詳細は `references/figma-extraction.md`。

対象フレームとその意味のある子孫について、Figma MCP で以下を取得:

- **構造** — 階層と意図する semantic 要素 (`button`、`link`、`heading`、`region` 等)
- **トークン** — 各視覚プロパティをトークン名で記録 (生の値は記録しない)
- **States** — Figma の variants に存在する全状態 (default、hover、focus、active、disabled、loading、empty、error 等)
- **A11y** — interactive 要素から推測される role、label、キーボード挙動
- **レスポンシブ** — 固定/可変/ブレークポイントの区別

トークンに紐付かないプロパティがあればフラグを立てる。トークンが不足している (ユーザーに報告) か、その値はそもそも存在すべきでないか、のどちらか。

## フェーズ 5: 実装

- 棚卸しした primitive を合成。新規低レベル実装には明示的な理由が必要。
- 最も近い隣接ファイルを模倣する: import の順序、型 export、props 命名、ファイル分割、default/名前付き export の方針、テスト/story の同居方法。
- **トークンのみ使用。** 実装内に hex、色名、`px`/`rem` の数値が出てきたら(トークン定義ファイル以外で) 間違い。
- Figma に存在する全 states を実装。default だけで止めない。

## フェーズ 6: Stories

`*.stories.{ts,tsx}` を追加または更新。どの state に専用 story を用意するかはタスクごとに判断:

- Figma の variant として異なる state → 専用 story (検証対象)
- 振る舞い的に DOM が変わる state (loading、error、empty) → 専用 story
- Storybook controls で十分カバーできる単なる props 順列 → スキップ(視覚検証のためにスクリプトで指定したい場合は除く)

Story 名は state を反映: `Default`、`Hover`、`Focus`、`Disabled`、`Loading`、`Error`、`Empty`。

## フェーズ 7: 検証

詳細は `references/storybook-verification.md`。

**Skill 配下の `node_modules` を使うため、初回のみ依存セットアップが必要 (マシンごとに 1 回)。**冪等なチェックを毎回回してよい:

```bash
if [ ! -d "${CLAUDE_SKILL_DIR}/node_modules/playwright" ]; then
  (cd "${CLAUDE_SKILL_DIR}" && npm install && npx playwright install chromium)
fi
```

検証フローはどのプロジェクトでも同じ:

1. プロジェクトで Storybook をバックグラウンド起動 (`npm run storybook -- --ci`)
2. `index.json` から対象 story の ID を取得 (URL は自動検出)
3. 各 story について、スクリプトが遷移し、story 名に応じて `hover` / `focus` を発火、設定済みビューポートでスクショ
4. Figma MCP で対応する variant のフレーム画像を取得
5. 並べて比較

スクリプトはプロジェクトルートを CWD として絶対パスで呼ぶ:

```bash
cd <project-root>
STORIES='[{"id":"button--default"}]' \
  node "${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs"
```

出力は `<project-root>/visual-check/` に保存される。

## フェーズ 8: 収束

2 段ゲート。

**構造チェック (機械的):**

- 対象 state すべてに story が存在する
- 実装に raw value がない (トークン定義ファイル外で hex / `\d+px` / `\d+rem` の正規表現チェック)
- a11y 属性がフェーズ 4 の仕様と一致 (role、label、`aria-*`)

**視覚チェック (Claude 判定):**

- 比較順: 構造 → 余白 → タイポグラフィ → 色 → state ごとの差分
- 最小トークン単位以上の差分があれば反復
- 明確な差分が残らなくなったら最終確認に進む

**最終確認の出し方:**

- **ユーザー直接起動の場合** — その場でユーザーに side-by-side を提示し最終確認を求める
- **`dev-task` 経由の場合** — ユーザー最終確認は実施せず、視覚反復が収束した時点で dev-task に制御を返す。Playwright スクショは `<project-root>/visual-check/` に残っているので、dev-task が型/ビルド/lint を通した後に同じ画像を参照してユーザー最終確認を行う。型エラー修正で実装が変わった場合は dev-task から再度 frontend-fidelity を起動し、視覚チェック反復からやり直す。

**ストップ条件:** 視覚反復は最大 3 回まで。それを超えても収束しないなら、残差をユーザーに提示して判断を仰ぐ。空回りより escalate を優先。

## References

- `references/figma-extraction.md` — Figma MCP の呼び出しと各レベルで取得すべきもの
- `references/design-system-discovery.md` — primitive 探索の戦略
- `references/token-map-inference.md` — Figma 変数とコードトークンの突合
- `references/storybook-verification.md` — Storybook + Playwright ループと画像比較、ゼロコンフィグ運用

## Scripts

- `scripts/screenshot-stories.mjs` — story を複数の state/ビューポートで撮る Playwright スクリプト。Skill 配下にインストールされた `playwright` を使うため、複数プロジェクトをゼロコンフィグで横断する。`${CLAUDE_SKILL_DIR}` 経由で呼ぶことで personal / project どちらの配置でも動く。
- `package.json` — Skill 自身が抱える Playwright 依存の宣言。初回 `npm install` 用。
