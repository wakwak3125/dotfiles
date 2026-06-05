---
name: dev-task
description: Linear チケット ID または自然言語で指定された開発タスクを、軽量(最小差分・過剰設計を避ける)かつ高品質(既存パターンに沿い、型/ビルド/テストが通る)に実装する。フロントエンド UI タスク(React TypeScript + Figma 起点)では、Figma MCP で仕様を抽出し Storybook + Playwright で視覚検証ループを回す。「ABC-123 を実装して」「このチケットお願い」「このバグ直して」「〜の対応を追加して」「動くようにして」「このデザインを実装して」「Figma から作って」「このコンポーネント作って」「ピクセルパーフェクトに」など、リポジトリ内のコード変更を伴う依頼で必ず発火する。plan mode で承認されたプランの実装開始時 (「Implement the following plan」等、スキル外で作られたプランを含む) も必ず発火し、承認済みプランを作業仕様としてフェーズ 4 以降 (担当判断・検証・レビュー・コミット) を適用する。Kotlin バックエンド、React TypeScript フロントエンド、protobuf スキーマ、Node.js サービスを主対象。ユーザーが「実装」と明言しなくても、具体的なコード変更依頼であれば常に使うこと。
---

# dev-task

開発タスクを軽量かつ高品質に実装する Skill。

入力は 3 形式:

- **Linear チケット ID** (`[A-Z]+-\d+` 形式) → Linear MCP でチケット本体・コメント・関連 diff・親プロジェクトを取得
- **自然言語の説明** → メッセージから意図と受け入れ条件を抽出
- **承認済みプラン** (plan mode 承認後の「Implement the following plan」等) → プランを作業仕様として扱い、*承認済みプランからのエントリ* に従ってフェーズ 4 から開始

対象スタック: バックエンド Kotlin、フロントエンド React TypeScript、必要に応じて protobuf と Node.js。

**フロントエンド UI タスク** (Figma 起点の React TypeScript 実装) はフェーズ 4 に UI 専用のサブフェーズ (4a〜4g) が挟まり、Figma MCP で仕様抽出 → Storybook + Playwright で視覚検証ループを回す。Playwright は本 Skill 配下にインストールされ、複数プロジェクトで共有される (初回のみマシン単位で 1 回 install)。

**実装の担い手はレイヤー (フロント / バック) で固定しない。** タスクの性質に応じてメイン (Claude) と Codex を使い分ける。Claude は「設計判断・UI 実装・見た目調整・既存コード理解・曖昧仕様からの初稿」、Codex は「確定した計画の完遂・型/lint/テスト修正・機械的な置換や整理」が得意。判断軸の詳細はフェーズ 4〜6 を参照。委譲は forge skill 経由に固定する。

## ワークフロー

1. **入力解決** — Linear チケットまたは自然言語から作業仕様(課題 + 受け入れ条件)を構築
2. **コンテキスト収集** — 関連ファイル・既存パターン・類似実装を探索。UI タスクか判定
3. **トリアージ** — 直接実装するか、プラン承認後に実装するかを判定
3.5. **プラン作成 (条件付き)** — PLAN_REQUIRED 時のみ plan mode に入り、`dev-task-planner` subagent を起動。ExitPlanMode でプラン承認を取る
4. **実装** — *実装ルール*に従う。タスクの性質でメイン (Claude) か Codex かを選ぶ (UI / 設計判断はメイン、確定計画の機械的完遂は Codex)。委譲は forge skill 経由。UI タスクの場合は *UI サブフェーズ* (4a〜4g) を実行
5. **検証** — プロジェクトが対応する型/ビルド/テスト/lint を実行。機械的な失敗修正ループは Codex に委譲可
6. **レビュー (条件付き)** — trivial 変更を除き、Claude reviewer 2 体 (correctness / style) を**並列起動**し、Codex レビューを併用
7. **コミット・プッシュと完了報告** — 適切な粒度で commit/push (デフォルトブランチ上なら wt で機能ブランチを自動作成)。PR は作らず別途指示を待つ。UI タスクは side-by-side で最終確認

上の 7 フェーズは**省略不可の品質ゲート**であって、可変のタスクリストではない。何を作るか (作業タスク) はタスクごとにエージェントが判断するが、フェーズの順序と通過は固定で守る。特に **trivial 以外は検証 (5)・レビュー (6) を飛ばさない**。実装が長く進捗の可視化が要る規模なら、ハーネスの Task tool (TaskCreate / TaskUpdate) で任意に管理してよい (応答へのチェックリスト転記は不要)。

### 承認済みプランからのエントリ

plan mode の承認を経て実装が始まる場合 (「Implement the following plan」等)、プランが本 Skill のフェーズ 3.5 由来かどうかに関わらず、**フェーズ 4 以降のゲートをすべて適用する**:

- **フェーズ 1〜3.5 はスキップ**してよい。承認済みプランを作業仕様 (課題 + 受け入れ条件 + 設計判断) として扱う。プランに受け入れ条件が明記されていなければ、プラン本文から抽出して仮定を記録する
- **フェーズ 4 の担当判断 (メイン / Codex) は省略しない。** プランが承認済みということは「確定した実装計画」なので、Codex 委譲の有力候補になる (UI / 既存コードの深い読み解きが要る部分はメイン)。判断理由を最終報告に 1 行残すのも通常通り
- **フェーズ 5 (検証)・フェーズ 6 (レビュー)・フェーズ 7 (コミット) も通常通り通過する。** trivial スキップ条件の判定基準も同一

「プランは承認済みだからそのまま直接実装してよい」は誤り。承認はプラン内容への承認であって、品質ゲート (担当判断・検証・レビュー) の免除ではない。

## フェーズ 1: 入力解決

メッセージに Linear チケット ID が含まれる場合:

- Linear MCP でチケット本体とコメントを取得。関連 diff、添付、参照されている親プロジェクトの説明も読む。
- 抽出する情報: 課題、受け入れ条件、言及されているファイル/コンポーネント、関連チケット。

自然言語の場合:

- 自己確認のためタスクを 1 行で言い直す。自明な場合は確認待ちで止まらない。
- 分類する: バグ修正 / 機能追加 / リファクタ / 設定変更 / UI 実装。

受け入れ条件が欠落または曖昧な場合、**質問返しせず仮定を明示的に記録する**。非自明な変更であればプラン提示時にユーザーに見せる。

## フェーズ 2: コンテキスト収集

コードに触れる前に:

- 影響範囲のレイヤーを特定: バックエンド Kotlin / フロント React-TS / proto / Node.js (複数のことも多い)
- 該当箇所を特定: ファイル glob、タスクのキーワードで grep、import / 使用箇所をたどる
- **類似する既存実装を最低 1 つ見つける。** これがフェーズ 4 で模倣すべきパターンになる
- 触れる言語領域ごとに、対応する `references/` を読む

### UI タスク判定

タスクが以下のいずれかを満たすなら **UI タスク** として扱い、フェーズ 4 で UI サブフェーズ (4a〜4g) を実行:

- Figma URL / フレーム / ノード ID が入力に含まれる
- React コンポーネント / ページ / Story の新規作成 or 視覚的変更が主目的
- 「ピクセルパーフェクト」「デザインに合わせて」「Figma から」等のキーワード

UI タスクなら追加で以下の references を読む:
- `references/figma-extraction.md`
- `references/design-system-discovery.md`
- `references/token-map-inference.md`
- `references/storybook-verification.md`

## フェーズ 3: トリアージ — 直接実装 or プラン提示

**直接実装してよい**条件 (すべて満たす):

- 期待挙動の解釈が一意に定まる
- 適用可能な類似パターンが見つかった
- 公開境界に触れない(HTTP API、proto スキーマ、DB スキーマ、イベント、export された型/シンボル)
- 副作用が局所的(共通ユーティリティ、認可ロジック、横断的関心事に触れない)

**プラン提示すべき**条件 (いずれか該当):

- 受け入れ条件に複数の妥当な解釈がある
- 実装に設計上の選択肢がある (既存拡張 vs 新規追加 / どの層に置くか / どのパターンを採用するか)
- 公開境界に触れる
- 参考パターンが見つからず、設計判断が必要
- 横断的または副作用の影響が読みづらい

プラン提示が必要な場合は、フェーズ 3.5 へ。それ以外はフェーズ 4 へ直接進む。

## フェーズ 3.5: プラン作成 (PLAN_REQUIRED のみ)

**まず plan mode に入る。** `EnterPlanMode` tool を呼んで plan mode に移行する (deferred tool の場合は ToolSearch で `select:EnterPlanMode,ExitPlanMode` をロードしてから呼ぶ。すでに plan mode で起動されている場合はそのまま進む)。これにより、承認前に実装へ進む事故が harness レベルでブロックされる。

次に `dev-task-planner` subagent を Agent tool で起動する。subagent には以下を構造化して渡す:

- **意図** — 1〜2 行の言い直し
- **受け入れ条件** — フェーズ 1 で抽出したリスト
- **影響範囲** — フェーズ 2 で特定したレイヤー (Kotlin / React-TS / proto / Node.js / UI)
- **類似実装** — フェーズ 2 で見つけた参照パターンのファイルパス
- **触る可能性のあるファイル glob**

planner はコードを書かず、プランだけを返す。**得られたプランを `ExitPlanMode` tool でユーザーに提示し、plan mode の承認 UI で明示的な承認を得てから**フェーズ 4 に進む。テキストでプランを貼って「承認しますか?」と聞くだけの運用は禁止 (必ず ExitPlanMode を経由する)。

- **承認された** → plan mode が解除されるので、フェーズ 4 へ進む
- **拒否 / 修正フィードバックが返った** → plan mode に留まったまま、フィードバックを反映したプランを再構成し、再度 ExitPlanMode で提示する。planner subagent の再起動は不要 (メインが差分を直接反映してよい)

承認後にユーザーから方針変更が入った場合も同様に、planner を再度起動するのではなく、メインがその差分を反映したプランを直接提示し直してよい。

## フェーズ 4: 実装ルール

言語によらず適用:

- **真似る、創るな。** 最も近い既存実装のファイル構造・命名・型・イディオムに合わせる。逸脱する場合は理由を明記。
- **最小差分。** 受け入れ条件が要求するものだけ変更。ついで整形、ついでリファクタ、関係ない依存更新はしない。
- **新しい抽象を導入しない。** タスクが明示的に求めていない限り、「念のため」のレイヤー追加は悪臭。
- **公開境界は不変。** それを変えること自体がタスクでない限り触らない。
- **型キャストでなく型修正。** `as` / `!!` / `any` / `unchecked` を避け、根本の型を直す。

言語別のルール:

- Kotlin → `references/kotlin.md`
- React TypeScript → `references/react-ts.md`
- protobuf → `references/protobuf.md`
- Node.js → `references/nodejs.md`

該当言語のコードを書く前に、対応する reference を読むこと。

### 実装の担当判断 — メイン (Claude) か Codex か

**レイヤー (フロント / バック) で固定せず、タスクの性質でベストな方を選ぶ。** Claude は「考える・既存に合わせる・整える」、Codex は「確定した作業を完遂・検証する」が得意。実装に着手する前にどちらが担うかを決め、判断理由を最終報告に 1 行残す。委譲する場合は Skill tool で `forge:forge` を起動して Codex に渡す。複数レイヤー / 複数サブタスクにまたがる場合は、性質ごとに担い手を分けて進めてよい。

**メイン (Claude) が直接実装する:**

- UI / フロントエンド実装・見た目調整 (React TypeScript の視覚的変更、Figma 起点、UI 微修正)。視覚検証ループ (4a〜4g) はメインで回す
- 設計判断を伴う実装 (層の選択・責務配置・パターン採用、大きめの設計変更、複雑な業務ロジック)
- 曖昧な仕様からの初稿、既存コードの深い読み解きを要する変更
- レイヤーを問わず「設計の意味を考えながら進める」必要があるもの

**Codex に委譲する:**

- 確定した実装計画の機械的完遂 (PLAN_REQUIRED で承認済み、または仕様が一意に固まっている非 UI 実装)
- 型エラー修正・lint 修正・決まった置換 / 整理 / import 整頓
- テスト追加 (正常系 / 異常系の網羅)
- 原因が特定済みの小さな bug fix、DB migration、deprecated API 置換
- レイヤーを問わず「やることが明確で、完遂力・検証ループが効く」もの

**判断デフォルト: 迷ったらメイン (Claude) で書く。** 設計 / 解釈の余地が少しでも残る、既存コードの読み解きが要る、と感じたらメイン。計画が確定し機械的に完遂できると言い切れるときだけ Codex に委譲する。

**上流は常にメインが固める。** フェーズ 1〜3.5 (理解・設計・プラン) はメイン専任で、Codex には委譲しない。Codex に渡すのは「何を・どう作るか」が確定した後の実装作業だけ。

**軽微な変更はメイン直接でよい** (Codex 委譲のオーバーヘッドを避ける)。目安はフェーズ 6 の trivial スキップ条件と同等 (変更ファイル数 2 以下 / 変更行数 30 行未満 / 公開境界に触れない)、または typo 修正・コメントのみ・設定値の単純差し替えなど。

**委譲経路は forge skill に固定する。** `codex:rescue` skill、`codex:codex-rescue` subagent、Bash での直接 `codex exec` 実行など、forge を経由しない Codex 委譲は本 Skill 内では禁止 (環境に codex プラグインが入っていても使わない)。

**Codex プロンプトにペルソナ設定を書かない (実装・検証・レビュー共通)。** 「あなたは経験豊富なシニアエンジニアです」「10年のレビュー経験を持つ〜」等の役割演出・キャラ付けは一切入れず、タスク事実 (課題・受け入れ条件・対象パス・diff・観点・出力形式) だけでプロンプトを構成する。

Codex に委譲するときの手順:

1. 対象レイヤーの reference (`references/kotlin.md` / `references/protobuf.md` / `references/nodejs.md`) を読んだ上で、**自己完結したプロンプト**を組み立てる (Codex は会話のコンテキストを一切持たない):
   - 課題と受け入れ条件 (フェーズ 1 の抽出結果)
   - 対象ファイル・関数のパス (フェーズ 2 で特定したもの)
   - 模倣すべき類似実装のパス (フェーズ 2 で見つけた参照パターン)
   - 適用すべき実装ルール — 本フェーズ冒頭の共通ルール (最小差分 / 新抽象禁止 / 公開境界不変 / 型修正) と対象レイヤーの reference の要点
   - PLAN_REQUIRED だった場合は承認済みプランの該当部分
   - 検証コマンド (Kotlin は `./gradlew compileKotlin`、Node.js は `npm run typecheck`、protobuf は `buf lint` / `buf breaking` 等、プロジェクトのもの)
2. forge skill (`/forge:codex` の手順) でプロンプトを渡し、実装させる。
3. 返ってきたら `git diff` で変更を確認し、メインが*実装ルール*への適合を検証する:
   - 最小差分か (無関係な変更・ついでリファクタが混ざっていないか)
   - 類似実装のパターンに沿っているか
   - 公開境界に触れていないか (宣言済みの場合を除く)
4. 違反や不足があれば、指摘内容を添えて forge に修正を再依頼する (**最大 2 回**)。それでも収束しなければメインが直接修正してよい。

委譲後のフェーズ 5 (検証)・フェーズ 6 (レビュー)・フェーズ 7 (コミット) はメインがオーケストレーションする (フェーズ 5・6 でも必要に応じて Codex を使う。詳細は各フェーズ参照)。reviewer のスキップ判定は委譲の有無に関わらず同じ基準を適用する。

**UI タスクの場合は、本フェーズの実装作業を以下のサブフェーズ 4a〜4g に分けて進める。** 非 UI タスクは通常通り実装してフェーズ 5 へ。

### フェーズ 4a: Figma 仕様抽出

詳細は `references/figma-extraction.md`。

対象フレームとその意味のある子孫について、Figma MCP で以下を取得:

- **構造** — 階層と意図する semantic 要素 (`button`、`link`、`heading`、`region` 等)
- **トークン** — 各視覚プロパティをトークン名で記録 (生の値は記録しない)
- **States** — Figma の variants に存在する全状態 (default、hover、focus、active、disabled、loading、empty、error 等)
- **A11y** — interactive 要素から推測される role、label、キーボード挙動
- **レスポンシブ** — 固定/可変/ブレークポイントの区別

ユーザーが画像しか貼っていない場合は、トークン抽出に live source が必要なのでリンクを要求する。

トークンに紐付かないプロパティがあればフラグを立てる。

### フェーズ 4b: token-map 構築/更新

詳細は `references/token-map-inference.md`。

要約: プロジェクトのトークン定義ファイル (`theme.{ts,js}`、`tokens.{ts,json}`、`tailwind.config.*`、CSS/SCSS の `:root { --... }` ブロック) を特定し、`name → value` テーブルにパース。Figma MCP で variables を取得し、値ベースで突き合わせ (名前類似度をタイブレーカに)、`/tmp/token-map.json` にセッション保存。トークン定義に変更があれば再構築。

突合不能が 30% を超える場合は、ユーザーにトークン対応 config のパスを尋ねてから続行する。

### フェーズ 4c: デザインシステム棚卸し

詳細は `references/design-system-discovery.md`。

**制約: 既存 primitive で合成可能なら、新しい低レベルコンポーネントを書かない。** 候補 primitive (`src/components`、`src/ui`、`packages/*/ui`、Storybook stories) を列挙し、合成案を提示してから実装に入る。

合成不能なら、その理由を明示してから新規 primitive 実装に着手。

### フェーズ 4d: 実装 + Story 追加

- 棚卸しした primitive を合成。新規低レベル実装には明示的な理由が必要。
- 最も近い隣接ファイルを模倣する: import の順序、型 export、props 命名、ファイル分割、default/名前付き export の方針、テスト/story の同居方法。
- **トークンのみ使用。** 実装内に hex、色名、`px`/`rem` の数値が出てきたら (トークン定義ファイル以外で) 間違い。
- Figma に存在する全 states を実装。default だけで止めない。

`*.stories.{ts,tsx}` を追加または更新。どの state に専用 story を用意するかはタスクごとに判断:

- Figma の variant として異なる state → 専用 story
- 振る舞い的に DOM が変わる state (loading、error、empty) → 専用 story
- Storybook controls で十分カバーできる単なる props 順列 → スキップ

Story 名は state を反映: `Default`、`Hover`、`Focus`、`Disabled`、`Loading`、`Error`、`Empty`。

### フェーズ 4e: 比較画像ペアの取得

視覚比較には **Playwright スクショ** と **Figma フレーム画像** の**両方**が必要。片方だけで比較してはいけない (片方比較は脳内テキスト照合になり、Figma にない要素を見逃す)。

出力ディレクトリ規約:

```
/tmp/dev-task-visual-check/<project-basename>/
  ├── <story-id>__<state>__<viewport>__playwright.png
  └── <story-id>__<state>__<viewport>__figma.png
```

`<project-basename>` は CWD のディレクトリ名。複数プロジェクトの並行作業に対応。命名はサフィックス (`__playwright` / `__figma`) で対称になる。

詳細は `references/storybook-verification.md` および `references/figma-extraction.md`。

#### 4e-1. Playwright スクショ取得

**Skill 配下の `node_modules` を使うため、初回のみ依存セットアップが必要 (マシンごとに 1 回)。**

依存がセットアップ済みかは存在チェックだけを実行する:

```bash
test -d "${CLAUDE_SKILL_DIR}/node_modules/playwright" \
  && test -d "${CLAUDE_SKILL_DIR}/node_modules/playwright-core" \
  && echo "playwright ready" \
  || echo "playwright NOT installed"
```

- **「ready」が出力されたら、`npm install` / `npx playwright install` を絶対に実行しない。** インストール済みなのに再実行すると権限プロンプトが発生して停止するだけのノイズ。次のスクリプト実行ステップへ進む。
- 「NOT installed」が出力された場合は、**ユーザーに確認してから**以下を実行する。auto-mode でも自動実行しない (Chromium binary は 200MB+ で時間も数分かかる、副作用が大きい操作):

```bash
(cd "${CLAUDE_SKILL_DIR}" && npm install && npx playwright install chromium)
```

検証フロー:

1. プロジェクトで Storybook をバックグラウンド起動 (`npm run storybook -- --ci`)
2. `index.json` から対象 story の ID を取得 (URL は自動検出)
3. 各 story について、スクリプトが遷移し、story 名に応じて `hover` / `focus` を発火、設定済みビューポートでスクショ

スクリプトはプロジェクトルートを CWD として絶対パスで呼ぶ:

```bash
cd <project-root>
STORIES='[{"id":"button--default"}]' \
  node "${CLAUDE_SKILL_DIR}/scripts/screenshot-stories.mjs"
```

出力は `/tmp/dev-task-visual-check/<project-basename>/<story-id>__<state>__<viewport>__playwright.png`。

#### 4e-2. Figma フレーム画像取得

**省略禁止。** Figma 画像なしで 4g に進むと visual-reviewer は判定不能 (NEEDS_REVISION) で返してくる。

各 story × state × viewport の組合せについて、Figma MCP で対応する variant 画像を取得し、Playwright と**完全に対称な命名**で保存する。

##### 命名規約 (絶対遵守)

Playwright スクショと Figma 画像のファイル名は **「`__playwright`」を「`__figma`」に置換しただけ**の関係でなければならない。それ以外の差異 (短縮形 / 大文字小文字 / 区切り文字) は禁止。

```
✅ 正しい例:
  features-order-nutrition-order-v2-drawer-mealcontenteditor--default__default__desktop__playwright.png
  features-order-nutrition-order-v2-drawer-mealcontenteditor--default__default__desktop__figma.png

❌ 違反パターン:
  state__hover-header.png                                 → story-id 欠落 + __figma サフィックス欠落
  mealcontenteditor--default__default__figma.png         → story-id を短縮、viewport も欠落
  editor__hover-column__figma.png                        → story-id 短縮
  Mealcontenteditor--Default__default__desktop__figma.png → 大文字混入 (Storybook の id は全小文字)
```

##### 厳守ルール

- `<story-id>` は **Storybook の `index.json` で取得した id を完全一致**で使う。プレフィックス (`features-order-...`) を含む全体。省略・短縮・大文字化はすべて禁止
- `<state>` は Playwright 側で使った値と完全一致 (`default` / `hover` / `focus` 等)
- `<viewport>` は Playwright 側で使った値と完全一致 (`desktop` / `mobile` / `drawer` 等)
- サフィックスは **必ず `__figma.png`** で終わる (`-figma.png`、`_figma.png`、サフィックスなしはすべて禁止)
- 解像度はビューポート幅と一致させる (最低 2x の rendering を要求)
- variant 名は Figma 側の `state=hover` 等と story 側 (`button--hover`) の対応を取る
- Figma フレーム外の余白や背景は含めない (フレーム単位で出力)

##### 命名の作り方 (確実な手順)

1. フェーズ 4e-1 で保存した Playwright スクショのパスを `ls /tmp/dev-task-visual-check/<project-basename>/*__playwright.png` で確認
2. 各ファイル名の `__playwright.png` を `__figma.png` に置換した文字列をそのまま Figma 画像の保存先とする
3. 保存後、4e-3 のペア存在チェックで揃っていることを必ず確認

#### 4e-3. ペア存在チェック

各 story × state × viewport について、`__playwright.png` と `__figma.png` の**両方**が存在することを Bash で確認:

```bash
DIR="/tmp/dev-task-visual-check/$(basename "$(pwd)")"
ls "$DIR"/*__playwright.png | while read pw; do
  fig="${pw%__playwright.png}__figma.png"
  [ -f "$fig" ] || echo "missing: $fig"
done
```

欠けているペアがあれば 4e-2 に戻る。**揃わない限り 4f には進まない。**

### フェーズ 4f: 構造チェック (機械的)

- 対象 state すべてに story が存在する
- 実装に raw value がない (トークン定義ファイル外で hex / `\d+px` / `\d+rem` の正規表現チェック)
- a11y 属性がフェーズ 4a の仕様と一致 (role、label、`aria-*`)

違反があれば 4d に戻る。

### フェーズ 4g: 視覚比較 (subagent 委譲)

`dev-task-visual-reviewer` subagent を Agent tool で起動して視覚比較を委譲する。**実装した本人ではない第三者**として、トークン単位の差分を判定する。

subagent に渡す情報:

- **プロジェクトルート** — 絶対パス
- **比較画像ディレクトリ** — `/tmp/dev-task-visual-check/<project-basename>/` (Playwright と Figma の両方を含む)
- **対象 story × state × viewport リスト** — 各組合せで `__playwright.png` と `__figma.png` が揃っている前提
- **Figma semantic 要素リスト** — フェーズ 4a で抽出した構造情報 (テキスト)。**余剰要素検出のために必須**
- **トークン情報 (任意)** — `/tmp/token-map.json` のパス

subagent は判定 (PASS / NEEDS_REVISION / 判定不能) と差分リストを返す。**Figma 画像が欠けていた場合、subagent は PASS を返さない。**

**視覚反復ループ:**

- **NEEDS_REVISION** → must 指摘を反映して実装を修正、フェーズ 4e (スクショ再取得) → 4f → 4g を再実行
- **PASS** → フェーズ 5 へ

**ストップ条件:** 4g 反復は最大 3 回 (subagent 起動回数 = 反復回数)。それを超えても収束しないなら、subagent が返した残差をそのままユーザーに提示して判断を仰ぐ。空回りより escalate を優先。

## フェーズ 5: 検証

プロジェクトが対応する範囲で、以下の順に実行:

1. **型チェック / コンパイル** — `./gradlew compileKotlin`、`tsc --noEmit`、`npm run typecheck`、`buf lint` / `buf breaking`
2. **ビルド** — `./gradlew build`、`npm run build`
3. **関連テスト** — 変更箇所をカバーするテストのみ。変更範囲が広い、またはユーザーが要求した場合のみ全件実行。
4. **lint / フォーマット** — プロジェクト定義のコマンド (`./gradlew ktlintCheck`、`npm run lint` 等)

失敗したら修正して再実行する。**機械的に潰せる失敗 (型不一致、import 不足、lint 違反、明確な assertion ずれ) の修正ループは Codex が得意なので、forge skill で Codex に委譲してループを回させてよい。** 失敗が設計の見直しを示唆する場合 (仕様の取り違え、責務配置の誤り) はメインが判断する。フェーズ 4 を Codex に委譲した実装なら、検証失敗の修正も同じ流儀で Codex に続けさせる。メインが直接書いた実装 (UI 等) は、文脈を持つメインがそのまま直す方が速いことが多い。

**UI タスクで型エラー修正により実装が変わった場合は、フェーズ 4e (スクショ再取得) → 4f → 4g (視覚比較) を再実行。**

## フェーズ 6: レビュー (trivial 変更を除く)

フェーズ 5 を通過したら、観点の異なる 3 つのレビューを併用する:

- **`dev-task-reviewer-correctness` (Claude subagent)** — 正確性・エッジケース・型安全性・セキュリティ・テスト網羅性
- **`dev-task-reviewer-style` (Claude subagent)** — 既存パターン整合・最小差分・公開境界不変・命名
- **Codex レビュー (forge skill)** — 機械的・網羅的チェック。明らかなバグ、認可漏れ、例外処理漏れ、境界条件、テスト不足を拾わせる。Codex は PR レビューが得意なので、メインが統合判断する前の網羅パスとして使う

2 つの Claude subagent は **1 メッセージ内で Agent tool を 2 つ並べて並列起動**する (シリアル起動は禁止)。Codex レビューは forge skill で並行して依頼し、`git diff` (比較ベースを明示) と受け入れ条件を自己完結プロンプトに含める。Codex は会話のコンテキストを持たないため、判定の根拠となる情報はすべてプロンプトに書く。

### trivial 変更のスキップ条件

以下のすべてを満たす変更は **レビュー (Claude subagent 2 体 + Codex の両方) をスキップ**してよい:

- 変更ファイル数が 2 以下、かつ
- 変更行数 (追加 + 削除) が 30 行未満、かつ
- 公開境界 (HTTP API / proto / DB / export 型) に触れていない

または、メインエージェントが **「レビュー不要」と理由付きで明示宣言**した場合もスキップしてよい (例: typo 修正、コメントのみの変更、設定値の単純差し替え)。宣言は最終報告に 1 行残す。

判断に迷ったら **スキップしない**。

### 各レビューに渡す情報

3 者共通:

- **受け入れ条件** — フェーズ 1 で抽出したリスト
- **比較ベース** — `git diff HEAD` で見るなら指定なし、`git diff <base>...HEAD` なら base を明示

`reviewer-correctness` 固有:
- **仮定** — フェーズ 1 / 3.5 で置いた仮定 (あれば)

`reviewer-style` 固有:
- **類似実装パス** — フェーズ 2 で見つけた参照パターン
- **公開境界の変更宣言** — プラン段階で「触る」と宣言した境界 (なければ「触らない」)

Codex レビュー固有 (forge プロンプトに明記):
- **diff 全体** — Codex はリポジトリ文脈を持たないため、レビュー対象の差分を渡す
- **重点観点** — バグ・認可漏れ・例外処理漏れ・境界条件・テスト不足
- **出力形式** — 指摘ごとに重大度 (重大 / 軽微) とファイル:行を付けて返すよう指示
- **ペルソナ禁止** — フェーズ 4 のプロンプト共通ルールの通り、役割演出は入れず事実と観点のみで構成する

### レビュー結果の処理

3 つのレビューの判定をまとめて評価する。Codex の指摘は PASS / NEEDS_REVISION 形式とは限らないので、メインが重大度を判定して must / imo 相当に振り分ける:

- **全員 PASS かつ Codex に重大指摘なし** → フェーズ 7 へ
- **いずれかに NEEDS_REVISION / 重大指摘** → must 相当を反映して修正、フェーズ 5 から再実行
- **再修正後の再レビューは 2 回まで**。2 回目でもまだ未解消の must が残るなら、残差をユーザーに提示して判断を仰ぐ (空回りより escalate を優先)

imo 指摘 (Claude reviewer の imo、Codex の軽微指摘) は採用 / 不採用をメインが判断する。不採用にする場合は理由を最終報告に残す。

**UI タスクでレビューの must 指摘により実装が変わった場合は、フェーズ 4e → 4f → 4g を再実行。**

## フェーズ 7: コミット・プッシュと完了報告

ローカルチェック通過 (+ 該当時は reviewer PASS) で実装完了とする。完了後、変更を**適切な粒度で commit し、push する**。**PR は作らない** (別途ユーザーが指示する)。

**UI タスクの場合**: コミット前に `/tmp/dev-task-visual-check/<project-basename>/` に残っている Playwright スクショと Figma フレーム画像を side-by-side で見せ、ユーザー最終確認を求める。

### 7-1. ブランチ確認

`git branch --show-current` で現在ブランチを確認する。

- **機能ブランチ上 (デフォルトブランチ以外)** → そのまま 7-2 へ。worktree 運用では起動時点で機能ブランチにいるのが通常ケース。
- **デフォルトブランチ上 (`master` / `main` / `develop`)** → デフォルトブランチへの直接コミットを避け、wt で機能ブランチを自動作成してからそちらでコミットする。手順:
  1. ブランチ名を決める。いずれも `wakwak3125/` プレフィックスを付ける:
     - **Linear チケットモード** → `wakwak3125/<チケット ID>-<slug>` (例: `wakwak3125/EMRK-123-add-dark-mode`)
     - **自然言語モード** → `wakwak3125/<slug>` (例: `wakwak3125/add-dark-mode`)
     - `<slug>` はタスク内容を表す kebab-case の短い語句。
  2. worktree は別ディレクトリに新規に切るため、現在の作業ツリーにある未コミット変更を退避して持ち越す。
     worktree の配置はリポジトリの既存慣例に合わせる (例: `<repo-parent>/worktree/<repo>/<slug>`。
     `git worktree list` で既存の配置を確認して揃える):
     ```bash
     wt_path=<repo-parent>/worktree/<repo>/<slug>
     git stash push -u -m dev-task-autobranch
     git worktree add -b <branch> "$wt_path" <default-branch>
     git -C "$wt_path" stash pop
     ```
     `wt` (インタラクティブ zsh 関数) は非対話シェルから呼べないため、`git worktree add` を直接使う。
  3. 以降の commit/push はこの worktree 内で行う (`git -C "$wt_path" ...` または `wt_path` を cwd にする)。

### 7-2. コミット

変更を**適切な粒度で commit** する:

- 論理的にまとまった単位で分割し、無関係な変更を 1 コミットに混ぜない。レイヤーの異なる変更 (proto / backend / frontend) やリファクタと機能追加は別コミットにする。
- trivial な単一目的の変更は 1 コミットでよい。
- メッセージは conventional commits スタイル (日本語可)。サマリはタスクの意図 (WHY) を表す。Linear チケットがあれば本文にチケット ID を記す。コードと同じく、コミットメッセージにも「今回の修正で」等の冗長表現は入れない。
- 機密ファイル (.env、credentials 等) はコミットに含めない。

### 7-3. プッシュ

現在ブランチを origin に push する。upstream 未設定なら `-u origin <branch>` で設定する。

### 7-4. 完了報告

最終結果、作成したコミット、push 先ブランチ (および 7-1 で worktree を作った場合はそのパス) をユーザーに報告する。PR は明示依頼があるまで作らない。

## References

非 UI:

- `references/kotlin.md`
- `references/react-ts.md`
- `references/nodejs.md`
- `references/protobuf.md`

UI (フェーズ 4a〜4g で参照):

- `references/figma-extraction.md` — Figma MCP の呼び出しと各レベルで取得すべきもの
- `references/design-system-discovery.md` — primitive 探索の戦略
- `references/token-map-inference.md` — Figma 変数とコードトークンの突合
- `references/storybook-verification.md` — Storybook + Playwright ループと画像比較、ゼロコンフィグ運用

## Scripts

- `scripts/screenshot-stories.mjs` — story を複数の state/ビューポートで撮る Playwright スクリプト。Skill 配下にインストールされた `playwright` を使うため、複数プロジェクトをゼロコンフィグで横断する。`${CLAUDE_SKILL_DIR}` 経由で呼ぶ。
- `package.json` — Skill 自身が抱える Playwright 依存の宣言。初回 `npm install` 用 (UI タスク時のみ)。
