---
name: dev-task
description: Linear チケット ID または自然言語で指定された開発タスクを、軽量(最小差分・過剰設計を避ける)かつ高品質(既存パターンに沿い、型/ビルド/テストが通る)に実装する。フロントエンド UI タスク(React TypeScript + Figma 起点)では、Figma MCP で仕様を抽出し Storybook + Playwright で視覚検証ループを回す。「ABC-123 を実装して」「このチケットお願い」「このバグ直して」「〜の対応を追加して」「動くようにして」「このデザインを実装して」「Figma から作って」「このコンポーネント作って」「ピクセルパーフェクトに」など、リポジトリ内のコード変更を伴う依頼で必ず発火する。plan mode で承認されたプランの実装開始時 (「Implement the following plan」等、スキル外で作られたプランを含む) も必ず発火し、承認済みプランを作業仕様としてフェーズ 4 以降 (担当判断・検証・レビュー・コミット) を適用する。Kotlin バックエンド、React TypeScript フロントエンド、protobuf スキーマ、Node.js サービスを主対象。ユーザーが「実装」と明言しなくても、具体的なコード変更依頼であれば常に使うこと。
---

# dev-task

開発タスクを軽量 (最小差分) かつ高品質 (既存パターン準拠、型/ビルド/テスト通過) に実装する Skill。

## 実行原則 (全フェーズ共通)

長時間・多フェーズになりやすく、高 effort ほど深追いしやすい Skill なので、以下を全フェーズで守る:

- **判断材料が揃ったら動く。** 会話・workspec・tool 結果ですでに確定した事実を再導出しない。選択に迷うときは追わない選択肢を並べ立てず、1 案に絞って根拠を残す (網羅列挙でなく推奨)。
- **進捗の主張は tool 結果で裏取りする。** 「型チェック通過」「テスト green」「視覚 PASS」「commit / push / PR 済み」等を報告する前に、根拠になる tool 結果がこのセッションにあるか確認する。未検証なら「未検証」と明示し、失敗は出力を添えてそのまま報告する。飛ばしたステップは飛ばしたと書く。憶測で "done" と書かない。
- **止まるのは本当に必要なときだけ。** 破壊的・不可逆な操作、スコープの実質変更、ユーザーにしか出せない入力 — これらに当たったときだけ手を止めて確認する。それ以外の曖昧さは仮定を記録して進める (質問返しで止めない)。空回りが 2〜3 回続いたら escalate。
- **ターンを閉じる前に最後の段落を点検する。** それが未着手の作業についての宣言・計画・次の手順・「次は〜する」の約束になっていたら、その場で tool を呼んで実行してから閉じる。テキストだけの意思表明でターンを終えない。

## Runtime adapter

最初に実行主体を判定し、対応する adapter を読む。以降、ホスト固有の tool / subagent / プラン作成手順 / Skill ディレクトリ解決は adapter を優先する。

- Claude Code で実行中 → `references/runtime-claude-code.md`
- Codex で実行中 → `references/runtime-codex.md`

共通手順内の `${DEV_TASK_SKILL_DIR}` は adapter が定義する dev-task Skill ディレクトリを指す。Claude Code 固有の `CLAUDE_SKILL_DIR` を共通手順へ直接持ち込まない。

入力は 4 形式:

- **Linear チケット ID** (`[A-Z]+-\d+` 形式) → Linear MCP でチケット本体・コメント・関連 diff・親プロジェクトを取得
- **自然言語の説明** → メッセージから意図と受け入れ条件を抽出
- **承認済みプラン** (plan mode 承認後の「Implement the following plan」等) → *承認済みプランからのエントリ* に従いフェーズ 4 から開始
- **複数ユニット (バッチ)** — チケット/依頼が 2 件以上 → フェーズ 0 で `dev-task-worker` へ 1 ユニットずつ委譲

対象スタック: バックエンド Kotlin、フロントエンド React TypeScript、必要に応じて protobuf と Node.js。Figma 起点の UI タスクはフェーズ 4 が UI サブフェーズ (4a〜4g) に分かれ、Figma MCP で仕様抽出 → Storybook + Playwright で視覚検証ループを回す。

## ワークフロー

0. **バッチ検知・ディスパッチ (複数ユニット時のみ)** — 2 件以上なら各ユニットを `dev-task-worker` へ委譲し、メインは集約・横断整合に専念。単一ユニットはこのフェーズを飛ばす
1. **入力解決** — 作業仕様 (課題 + 受け入れ条件) を構築
2. **コンテキスト収集** — 関連ファイル・類似実装を探索し、UI タスクか判定
3. **トリアージ** — 直接実装か、プラン承認後の実装かを判定
3.5. **プラン作成 (PLAN_REQUIRED のみ)** — プランを作成して workspec に記録し、人間の承認を待たずにフェーズ 4 へ進む
4. **実装** — *実装ルール*に従う。担当は UI / 曖昧仕様の初稿はメイン、それ以外は runtime adapter が許す場合に実装 subagent へ委譲。UI タスクはサブフェーズ 4a〜4g を実行
5. **検証** — 型/ビルド/テスト/lint。機械的な失敗修正ループは runtime adapter が許す場合に実装 subagent へ委譲可
6. **レビュー (trivial 除く)** — runtime adapter のレビュー手段で correctness / style を確認。設計判断が重い変更では別エンジンレビューを adapter が許す場合のみ併用
7. **コミット・プッシュ・draft PR 作成と完了報告** — 適切な粒度で commit/push (デフォルトブランチ上なら機能ブランチを自動作成) し、draft PR を作成する

7 フェーズは**省略不可の品質ゲート**であって、可変のタスクリストではない。作業タスクの中身はタスクごとに判断してよいが、フェーズの順序と通過は固定。特に **trivial 以外は検証 (5)・レビュー (6) を飛ばさない**。進捗の可視化が要る規模なら runtime adapter の進捗管理手段で任意に管理してよい (応答へのチェックリスト転記は不要)。

### 承認済みプランからのエントリ

plan mode 承認を経て実装が始まる場合、プランが本 Skill のフェーズ 3.5 由来かどうかに関わらず:

- **フェーズ 1〜3.5 はスキップ可。** 承認済みプランを作業仕様 (課題 + 受け入れ条件 + 設計判断) として扱う。受け入れ条件が明記されていなければプラン本文から抽出し、仮定を記録する。スキップしても **workspec の保存は行う** — 承認済みプランと抽出した受け入れ条件を `/tmp/dev-task/<project-basename>/workspec.md` に保存してからフェーズ 4 へ (subagent への受け渡しと compaction 耐性のため)
- **フェーズ 4 以降のゲートはすべて通常通り適用する。** 担当判断では「確定した実装計画」なので、runtime adapter が実装 subagent を提供する場合は原則委譲 (UI / 視覚調整のみメイン)。subagent がない実行主体ではメインが担当する。着手前の担当宣言、検証・レビュー・コミット、trivial 判定基準も通常と同一

承認はプラン内容への承認であって、品質ゲート (担当判断・検証・レビュー) の免除ではない。

## フェーズ 0: バッチ検知・ディスパッチ (複数ユニット時のみ)

入力に **2 件以上の独立したチケット/依頼**が含まれる場合のみ発火する。単一ユニットはこのフェーズを飛ばしてフェーズ 1 へ。目的は、各ユニットを `dev-task-worker` subagent に隔離実行させ、**メインはディスパッチ・タスク管理・横断整合に専念してメイン context を新鮮に保つ**こと (worker とその子で探索・実装・レビューを消費し、メインには各 worker のサマリだけが返る)。

バッチと判定する条件 (いずれか):

- チケット ID (`[A-Z]+-\d+`) が 2 件以上
- チケット/タスクのリストが明示的に渡された
- ユーザーが「まとめて」「これら全部」等でバッチを指示

runtime adapter が `dev-task-worker` を提供しない実行主体では、バッチに入らずユニットを 1 件ずつ通常フローで順に処理する。

手順:

1. **ユニット分解** — 各チケット/依頼を 1 ユニットに正規化し、runtime adapter の進捗管理手段 (Claude Code は `TaskCreate`) に登録する。
2. **依存判定** — ユニット間の依存グラフを作る。
   - **入力が Linear チケットの場合は Linear の関係を第一情報源にする** (Linear 依存モード)。各チケット取得時に `blocks` / `blocked by` / `parent` / `sub-issue` の関係も取得し、`blocked by` チェーンを依存辺とする。Linear の関係が真実で、コードからの推測 (proto→利用側、共有ライブラリ→利用側 等) は補助。
   - 自然言語ユニットや Linear 関係が無い場合は、コード推測のみで保守的に判定する (曖昧なら依存ありに倒す)。
   - **依存チェーンは blocker→blocked の順で直列化**する。ただし worker はデフォルトブランチ基点で worktree を切るため、blocked ユニットは **blocker がマージ済みであることが前提**。未マージのまま順序だけ守っても blocker の変更が worktree に入らないので、その場合はユーザーに提示して「blocker マージ後に blocked を流す」か判断を仰ぐ (blocker ブランチを base にする自動化はスコープ外)。
3. **共有ファイル衝突の事前検出** — 各ユニットが触る見込みのファイル集合 (touch-set) を軽量に見積もる (Linear の言及ファイル、runtime adapter が許すなら Explore subagent での read-only スコーピング)。**touch-set が重なるユニット同士は並列にせず同一の直列グループにまとめる** — worktree で編集は隔離できても最終マージで衝突するため。見積もりは不完全なので、取りこぼしは手順 7 の横断レビューで事後検出する。
4. **共有コンテキストの用意** — 全 worker に渡す共通事項 (リポジトリ規約・命名・スコープ境界・既知の依存) を 1 つにまとめる。パターンのブレを防ぐ。
5. **スケジューリング & 並列ディスパッチ** — 依存 (手順2) と衝突グループ (手順3) の制約を満たす範囲で、**互いに独立なユニットを並列度上限 (既定 4) まで 1 メッセージ内で並列 spawn** する。依存チェーン・衝突グループの内部は blocker→blocked / 順に直列。上限超過分はキューし、slot が空き次第起動する。各 worker は指定ブランチ名 (`wakwak3125/<slug>`)・作業仕様・共有コンテキストを受け取り、隔離 worktree でフェーズ 1〜7 を完遂してコンパクトなサマリを返す。
6. **集約** — 返ってきたサマリで各ユニットのタスク状態を更新する。worker の詳細 (探索・実装・レビューのログ) はメインに持ち込まない。
7. **横断整合レビュー (必須ゲート)** — 全 worker 完了後、サマリの「横断メモ」(触れた公開境界・共有ファイル・新規パターン) を突き合わせ、以下を必ず検査する:
   - **公開境界の二重変更** — 複数ユニットが同じ HTTP API / proto / DB / export 型を変えていないか
   - **共有ファイルの論理衝突** — 同一ファイルへの変更が意味的に矛盾しないか (手順 3 で見逃した重なりを含む)
   - **パターン乖離** — 同種の実装でユニット間の方針がブレていないか
   - **重複実装** — 複数ユニットが同じユーティリティ/コンポーネントを別々に作っていないか

   問題があれば該当 worker に修正を再委譲する (最大 2 回、収束しなければユーザーに提示)。
8. **完了報告** — 各ユニットの結果 (状態・PR URL・仮定)、横断整合の所見、依存/衝突で直列化・保留したユニットをまとめて報告する。

**このフェーズ自体は品質ゲートを課さない。** 品質ゲート (検証・レビュー) は各 worker 内のフェーズ 5・6 で適用される。メインの責務はディスパッチと整合性の統括。

既知の制約:

- 並列度は既定 4 (超過はキュー)。負荷やサマリ肥大を見て調整してよい。
- 共有ファイル衝突の事前検出 (手順 3) はヒューリスティック (実装前に正確な touch-set は分からない)。取りこぼしは手順 7 の横断レビューで事後検出する。
- 依存チェーンは Linear 関係 (or コード推測) から検出して直列化するが、blocker ブランチを base にする自動化はスコープ外。blocked ユニットは blocker マージ後に流す前提で、未マージならユーザー判断に委ねる。

## フェーズ 1: 入力解決

Linear チケット ID が含まれる場合:

- Linear MCP でチケット本体とコメントを取得。関連 diff、添付、参照されている親プロジェクトの説明も読む。
- 抽出する情報: 課題、受け入れ条件、言及されているファイル/コンポーネント、関連チケット。

自然言語の場合:

- 自己確認のためタスクを 1 行で言い直す。
- 分類する: バグ修正 / 機能追加 / リファクタ / 設定変更 / UI 実装。

受け入れ条件が欠落・曖昧なときは、置いた仮定を workspec に明記し、非自明な変更なら完了報告でユーザーに伝える (質問返しの是非は *実行原則* に従う)。

**フェーズ 1 の終わりに、作業仕様を `/tmp/dev-task/<project-basename>/workspec.md` に保存する** (`<project-basename>` は CWD のディレクトリ名)。内容は課題 / 受け入れ条件 / 仮定。以降のフェーズで追記する: フェーズ 3 で公開境界の変更宣言、フェーズ 3.5 で承認済みプラン。メインの会話 context だけに置かず、subagent を使う場合は planner / implementer / reviewer へ**このパスを渡す**。各担当に微妙に違う仕様が渡る事故を防ぎ、compaction 後もこのファイルが真実の源になる。

## フェーズ 2: コンテキスト収集

コードに触れる前に:

- 影響範囲のレイヤーを特定: バックエンド Kotlin / フロント React-TS / proto / Node.js (複数のことも多い)
- 該当箇所を特定: ファイル glob、タスクのキーワードで grep、import / 使用箇所をたどる
- **類似する既存実装を最低 1 つ見つける。** これがフェーズ 4 で模倣すべきパターンになる
- 触れる言語領域のうち、**メインが直接実装するもの**は対応する `references/` を読む。implementer に委譲する領域は reference のパスを subagent に渡すだけでよく、メインが読み込まない (フェーズ 4 の委譲手順を参照)。subagent がない実行主体ではメインが読む

探索範囲が広い場合 (複数ディレクトリの横断、命名規則が不明な検索) は、runtime adapter が許すなら該当箇所特定・類似実装探しを **Explore subagent に委譲**してよい。メインの context をオーケストレーション (理解・検証・レビュー統合) に温存するのが目的。結論 (パスと要点) だけ受け取り、ファイル全文をメインに持ち込まない。

### UI タスク判定

以下のいずれかを満たすなら **UI タスク** として扱い、フェーズ 4 で UI サブフェーズ (4a〜4g) を実行:

- Figma URL / フレーム / ノード ID が入力に含まれる
- React コンポーネント / ページ / Story の新規作成 or 視覚的変更が主目的
- 「ピクセルパーフェクト」「デザインに合わせて」「Figma から」等のキーワード

UI タスクなら追加で *References* の UI 4 ファイル (figma-extraction / design-system-discovery / token-map-inference / storybook-verification) を読む。

## フェーズ 3: トリアージ — 直接実装 or プラン作成

**直接実装してよい**条件 (すべて満たす):

- 期待挙動の解釈が一意に定まる
- 適用可能な類似パターンが見つかった
- 公開境界に触れない (HTTP API、proto スキーマ、DB スキーマ、イベント、export された型/シンボル)
- 副作用が局所的 (共通ユーティリティ、認可ロジック、横断的関心事に触れない)

**プラン作成すべき**条件 (いずれか該当):

- 受け入れ条件に複数の妥当な解釈がある
- 実装に設計上の選択肢がある (既存拡張 vs 新規追加 / どの層に置くか / どのパターンを採用するか)
- 公開境界に触れる
- 参考パターンが見つからず、設計判断が必要
- 横断的または副作用の影響が読みづらい

トリアージの結果 (公開境界に触れるか、触るならどこか) を workspec に追記する。プラン作成が必要ならフェーズ 3.5 へ。それ以外はフェーズ 4 へ直接進む。

## フェーズ 3.5: プラン作成 (PLAN_REQUIRED のみ)

**プランは設計の構造化と subagent への受け渡しのために作る。人間の承認は取らない** — 作成したプランを workspec に記録したら、そのままフェーズ 4 へ進む。承認 UI (Claude Code の `ExitPlanMode` 等) で実装開始の許可を待たない。

runtime adapter が planner subagent を提供する場合は `dev-task-planner` を起動し、以下を構造化して渡す。提供しない場合はメインが同じ入力でプランを作る:

- **作業仕様ファイルのパス** — フェーズ 1 で保存した workspec (意図・受け入れ条件・仮定)
- **影響範囲** — フェーズ 2 で特定したレイヤー (Kotlin / React-TS / proto / Node.js / UI)
- **類似実装** — フェーズ 2 で見つけた参照パターンのファイルパス
- **触る可能性のあるファイル glob**

planner / メインはコードを書かず、プランだけを返す。返ってきたプランを workspec に追記してフェーズ 4 へ進む。

- プランは作業仕様 (確定した実装計画) として扱う。フェーズ 4 以降の品質ゲート (担当判断・検証・レビュー) は通常どおり全て適用する。
- 設計上の選択肢が複数残る・受け入れ条件の解釈が割れるなど判断材料が足りない場合は、採用した選択肢とその根拠・棄却した代替案を workspec とプランに明記し、完了報告でユーザーに伝える (実装を止めて承認を待つのではなく、判断を記録して進める)。

ユーザーが**自分から** plan mode を使い、外部でプランを承認して実装を依頼してきた場合 (「Implement the following plan」等) は、*承認済みプランからのエントリ* に従いフェーズ 4 から進める。

## フェーズ 4: 実装ルール

言語によらず適用:

- **真似る、創るな。** 最も近い既存実装のファイル構造・命名・型・イディオムに合わせる。逸脱する場合は理由を明記。
- **最小差分。** 受け入れ条件が要求するものだけ変更。ついで整形、ついでリファクタ、関係ない依存更新はしない。
- **新しい抽象を導入しない。** タスクが明示的に求めていない限り、「念のため」のレイヤー追加は悪臭。
- **公開境界は不変。** それを変えること自体がタスクでない限り触らない。
- **型キャストでなく型修正。** `as` / `!!` / `any` / `unchecked` を避け、根本の型を直す。
- **起きえない事態への防御を書かない。** 内部コード・フレームワークの保証を信頼し、バリデーション / エラーハンドリング / フォールバックはシステム境界 (ユーザー入力・外部 API) にだけ置く。ありえない分岐のための握り・後方互換シム・feature flag を、コードを直接変えれば済む場面で足さない。

言語別ルール: Kotlin → `references/kotlin.md`、React TypeScript → `references/react-ts.md`、protobuf → `references/protobuf.md`、Node.js → `references/nodejs.md`。該当言語のコードを書く前に対応する reference を読むこと。

### 実装の担当判断 — メインか実装 subagent か

**実装作業のデフォルトは runtime adapter に従う。** Claude Code では `dev-task-implementer` subagent への委譲が基本。Codex ではメイン実装が基本で、利用可能な multi-agent tools がある場合だけ委譲してよい。レイヤー (フロント / バック) では固定しない。メインの仕事は上流 (フェーズ 1〜3.5: 理解・設計・プラン。ここは委譲しない)、委譲仕様の品質、委譲結果の検証。実装に着手する**前に**「担当: メイン / 実装 subagent、理由: 〜」を 1 行で宣言してから書き始める (事後の言い訳ではなく事前のゲート。最終報告にも残す)。複数レイヤー / サブタスクにまたがる場合は性質ごとに担い手を分けてよい。依存関係のないサブタスク同士は、runtime adapter が並列 subagent を提供する場合だけ並列起動してよい。依存があるもの (proto → 生成コード → 利用側など) は直列のまま。

**メインが直接実装してよいのは以下:**

- UI / フロントエンド実装・見た目調整 (React TypeScript の視覚的変更、Figma 起点、UI 微修正)。視覚検証ループ (4a〜4g) はメインで回す
- 仕様が曖昧で、ユーザーとの対話や探索的な試行を挟みながらでないと書けない初稿 (書きながら仕様が固まっていく類のもの)
- 実装 subagent が修正往復 2 回で収束しなかった場合の引き取り
- 軽微な変更 (委譲オーバーヘッドの回避。目安はフェーズ 6 の trivial スキップ条件と同等、または typo 修正・コメントのみ・設定値の単純差し替え)
- runtime adapter が subagent を提供しない実行主体での作業

**`dev-task-implementer` subagent に委譲する (上記以外のすべての実装):**

- 承認済みプラン (PLAN_REQUIRED) の実装 — **原則 subagent**
- 仕様が一意に固まっている非 UI 実装全般 (機能追加・bug fix・リファクタを含む。「機械的な作業」に限らない)
- 型エラー修正・lint 修正・決まった置換 / 整理 / import 整頓
- テスト追加 (正常系 / 異常系の網羅)
- DB migration、deprecated API 置換

runtime adapter が subagent を提供する場合は、迷ったら委譲する。「設計判断が要る」「既存コードの読み解きが要る」は委譲を避ける理由に**ならない** — 設計判断はフェーズ 1〜3.5 でメインが終えているべきで、読み解いた結果 (参照パターン・対象パス・適用ルール) は委譲仕様に書いて渡せる。

実装 subagent に委譲するときの手順:

1. **自己完結した実装仕様**を組み立てて runtime adapter の手段で `dev-task-implementer` を起動する。subagent はリポジトリを読めるが、設計の文脈は持たないので以下を渡す:
   - 作業仕様ファイルのパス (`/tmp/dev-task/<project-basename>/workspec.md` — 課題・受け入れ条件・仮定・承認済みプラン)
   - 対象ファイル・関数のパス、模倣すべき類似実装のパス (フェーズ 2 で特定したもの)
   - 広域調査の結論 — 「X の全使用箇所」「複数ディレクトリ横断の影響範囲」のような広い調査が必要なタスクでは、**メインが事前に Explore subagent で調査を済ませ、結論 (パス一覧と要点) を委譲仕様に含める**。implementer には `Agent` tool を渡していない (かつ実装前に context をファイルダンプで埋めたくない) ため、implementer 自身に広域 grep はさせない
   - 対象レイヤーの reference のパス (`${DEV_TASK_SKILL_DIR}/references/<layer>.md` を絶対パスに展開して渡す)。**メインが要約して渡さない** — 要約は情報を削り、メインの context も消費する。subagent に原文を読ませる
   - 検証コマンド (Kotlin は `./gradlew compileKotlin`、Node.js は `npm run typecheck`、protobuf は `buf lint` / `buf breaking` 等、プロジェクトのもの)
2. 返ってきたら `git diff` で変更を確認し、メインが*実装ルール*への適合を検証する: 最小差分か (無関係な変更・ついでリファクタの混入)、類似実装のパターンに沿っているか、公開境界に触れていないか (宣言済みの場合を除く)。
3. 違反や不足があれば、指摘内容を添えて同じ `dev-task-implementer` に修正を再依頼する (**最大 2 回**)。それでも収束しなければメインが直接修正してよい。

委譲後のフェーズ 5〜7 はメインがオーケストレーションする (フェーズ 5 の機械的修正は実装 subagent に続けさせてよい)。reviewer のスキップ判定は委譲の有無に関わらず同じ基準。

**UI タスクは本フェーズの実装作業をサブフェーズ 4a〜4g に分けて進める。** 非 UI タスクは通常通り実装してフェーズ 5 へ。

サブフェーズの依存関係: 4a (Figma 抽出) と 4c (デザインシステム棚卸し) は**独立なので並列に進める**。4c はコードベース探索なので、runtime adapter が許すなら Explore subagent への委譲を推奨 (4a の Figma MCP 呼び出しと同時に走らせる)。4b は 4a の variables 取得後。4d 以降は直列。

### フェーズ 4a: Figma 仕様抽出 — 詳細: `references/figma-extraction.md`

対象フレームと意味のある子孫から、構造 (semantic 要素) / トークン (生の値でなくトークン名) / states (variants の全状態) / a11y / レスポンシブを抽出し、構造化サマリを `/tmp/dev-task-visual-check/<project-basename>/spec.md` に保存する (4d の実装契約・4g の検証仕様。visual-reviewer へはこのパスを渡す)。

- ユーザーが画像しか貼っていない場合、トークン抽出に live source が必要なのでリンクを要求する
- トークンに紐付かないプロパティがあればフラグを立てる

### フェーズ 4b: token-map 構築/更新 — 詳細: `references/token-map-inference.md`

プロジェクトのトークン定義ファイルと Figma variables を突合し、`/tmp/dev-task-visual-check/<project-basename>/token-map.json` に保存する。突合不能が 30% を超えたら、ユーザーにトークン対応 config のパスを尋ねてから続行する。

### フェーズ 4c: デザインシステム棚卸し — 詳細: `references/design-system-discovery.md`

**既存 primitive で合成可能なら、新しい低レベルコンポーネントを書かない。** 候補 primitive を列挙し、Figma 要素 → 合成案の対応表を作ってから実装に入る。合成不能なら理由を明示してから新規 primitive に着手。

### フェーズ 4d: 実装 + Story 追加

- 棚卸しした primitive を合成し、最も近い隣接ファイルを模倣する (import 順・型 export・props 命名・ファイル分割・story 同居方法)。**トークンのみ使用** (トークン定義ファイル外の hex / px / rem は間違い)。**Figma に存在する全 states を実装** (default だけで止めない)
- `*.stories.{ts,tsx}` を追加/更新。state ごとの story 用意基準と命名は `references/storybook-verification.md` の「Story の用意基準」
- **4e に進む前に型チェック (`tsc --noEmit` 等) を通す。** 視覚ループ後の型エラー発覚は 4e〜4g が丸ごと手戻りになる (フェーズ 5 のフル検証は別途通常通り)

### フェーズ 4e: 比較画像ペアの取得 — 手順: `references/storybook-verification.md`

視覚比較には **Playwright スクショと Figma フレーム画像の両方**が必要 (片方だけは脳内テキスト照合になり、Figma にない要素を見逃す)。`/tmp/dev-task-visual-check/<project-basename>/` に `<story-id>__<state>__<viewport>__{playwright,figma}.png` の対称命名で揃える。

1. **4e-1 Playwright スクショ** — `scripts/screenshot-stories.mjs` を使う。依存は存在チェックのみ自動で、「deps ready」なら install を再実行しない。未インストールなら**ユーザー確認後に** install (Chromium 200MB+、auto-mode でも自動実行しない)。**viewport は Figma に存在する breakpoint だけを `VIEWPORTS` で明示**し、幅は Figma フレーム幅に合わせる (デフォルトの mobile+desktop をそのまま使わない)
2. **4e-2 Figma フレーム画像 (省略禁止)** — 各ペアの variant 画像を Figma MCP で取得 (story 側 `button--hover` ⇔ Figma 側 `state=hover`)。フレーム単位・2x rendering。ファイル名は **Playwright 側の `__playwright.png` を `__figma.png` に機械的に置換しただけ**にする (規約詳細と正誤例: `references/figma-extraction.md` の「検証用フレーム画像」)。**一度取得した Figma 画像は反復をまたいでキャッシュ流用する** (Figma 側のデザインが変わったときだけ再取得)
3. **4e-3 ペア存在チェック** — 全ペアで両画像の存在を Bash で確認 (スニペットは reference 内)。**揃わない限り 4f に進まない**

### フェーズ 4f: 構造チェック + 機械的画像 diff

subagent (4g) に入る前に、機械的に検証できるものをすべてここで潰す:

- 対象 state すべてに story が存在 / 実装に raw value がない (トークン定義ファイル外の hex / `\d+px` / `\d+rem` を正規表現チェック) / a11y 属性が 4a の仕様と一致 — 違反は 4d に戻る
- **機械的画像 diff** — `node "${DEV_TASK_SKILL_DIR}/scripts/diff-pairs.mjs"` (CWD はプロジェクトルート) で各ペアの `__diff.png` と diff 率を生成。`dimensionMismatch` は取得条件のずれなので 4e に戻る。diff 率は注視箇所の手がかりで、**PASS / NEEDS_REVISION の判定は 4g が行う** (diff 率が低くても要素の混入・欠落はあり得る)

### フェーズ 4g: 視覚比較 (subagent 委譲)

runtime adapter が `dev-task-visual-reviewer` subagent を提供する場合は起動し、**実装した本人ではない第三者**としてトークン単位の差分を判定させる。提供しない場合は、メインが同じ入力で視覚比較する。渡す / 使う情報: プロジェクトルート / 比較画像ディレクトリ / 対象ペアリスト / `spec.md` のパス (**余剰要素検出に必須**) / 4f の diff 率サマリ / 前回の must リスト (反復 2 回目以降、解消確認を最初に行わせる) / token-map のパス (任意)。Figma 画像が欠けていた場合、PASS 扱いしない。

- **ペア分割並列化:** ペアが **8 を超えたら 1 context に全部詰めない**。runtime adapter が並列 subagent を提供する場合は story 単位のチャンク (≤ 8 ペア) に分けて並列起動し、メインが判定を統合 (全 PASS → PASS)。提供しない場合は同じチャンク単位で順に比較する。画像は最もトークンを食う入力で、1 context に詰めるほど後半の比較精度が落ちる。再反復は NEEDS_REVISION だったチャンクのみ
- **視覚反復ループ:** NEEDS_REVISION → must を修正し、4e-1 (影響を受けた story のみ撮り直し、Figma 画像は流用) → 4f → 4g を再実行。PASS → フェーズ 5 へ
- **subagent が判定する場合、メインは反復中に画像を直接 Read しない。** 判断は差分リストと diff 率で行い、画像を見るのはフェーズ 7 の最終確認だけ
- **ストップ条件:** 反復は最大 3 回。収束しなければ残差をユーザーに提示して判断を仰ぐ

## フェーズ 5: 検証

プロジェクトが対応する範囲で、以下の順に実行:

1. **型チェック / コンパイル** — `./gradlew compileKotlin`、`tsc --noEmit`、`npm run typecheck`、`buf lint` / `buf breaking`
2. **ビルド** — `./gradlew build`、`npm run build`
3. **関連テスト** — 変更箇所をカバーするテストのみ。変更範囲が広い、またはユーザーが要求した場合のみ全件実行。
4. **lint / フォーマット** — プロジェクト定義のコマンド (`./gradlew ktlintCheck`、`npm run lint` 等)

失敗したら修正して再実行する。機械的に潰せる失敗 (型不一致、import 不足、lint 違反、明確な assertion ずれ) の修正ループは、runtime adapter が許す場合に `dev-task-implementer` subagent へ委譲してよい。フェーズ 4 を subagent に委譲した実装なら検証失敗の修正も subagent に続けさせ、メインが直接書いた実装 (UI 等) は文脈を持つメインがそのまま直す。失敗が設計の見直し (仕様の取り違え、責務配置の誤り) を示唆する場合はメインが判断する。

**UI タスクで型エラー修正により実装が変わった場合は、4e-1 (影響を受けた story のみ撮り直し、Figma 画像は流用) → 4f → 4g (視覚比較) を再実行。**

## フェーズ 6: レビュー (trivial 変更を除く)

フェーズ 5 を通過したら、runtime adapter のレビュー手段で correctness / style の 2 観点を確認する。Claude Code では観点の異なる 2 つの Claude reviewer を**基本**とし、設計判断が重い変更でのみ codex レビュー (codex-plugin-cc) を任意で併用する。Codex では `references/runtime-codex.md` の self-review 手順に従う:

- **`dev-task-reviewer-correctness` (Claude subagent)** — 正確性・エッジケース・型安全性・セキュリティ・テスト網羅性
- **`dev-task-reviewer-style` (Claude subagent)** — 既存パターン整合・最小差分・公開境界不変・命名
- **codex レビュー (任意併用)** — 下記「codex レビューの併用判断」の条件を満たすときだけ追加する独立エンジンの網羅パス

runtime adapter が reviewer subagent を提供する場合、2 つの reviewer は **1 メッセージ内で並列起動**する (シリアル起動は禁止)。codex を併用する場合は同じタイミングで起動してよい。

### codex レビューの併用判断 (任意)

**以下のいずれかに該当するときだけ**、独立した別エンジンの網羅パスとして codex レビューを足す (review / adversarial-review の使い分け・companion の起動方法・fallback: `references/codex-review.md`):

- 公開境界 (HTTP API / proto / DB / export 型) に触れる
- 設計上の選択肢を取った (新規抽象の導入、新パターンの採用、層配置の判断)
- 認可・トランザクション・並行性など、壊れたときの影響が大きいロジック
- PLAN_REQUIRED だったタスク

該当しない通常変更では runtime adapter の基本レビューで十分。codex 未導入 / 未セットアップ / Codex 自身が実行主体の場合はスキップし、その旨を最終報告に 1 行残す。trivial 変更ではそもそもレビュー自体をスキップする (下記)。

### trivial 変更のスキップ条件

以下のすべてを満たす変更は **レビュー (runtime adapter の reviewer・codex とも) をスキップ**してよい:

- 変更ファイル数が 2 以下、かつ
- 変更行数 (追加 + 削除) が 30 行未満、かつ
- 公開境界 (HTTP API / proto / DB / export 型) に触れていない

または、メインエージェントが **「レビュー不要」と理由付きで明示宣言**した場合もスキップしてよい (例: typo 修正、コメントのみの変更、設定値の単純差し替え)。宣言は最終報告に 1 行残す。

判断に迷ったら **スキップしない**。

### 各レビューに渡す情報

reviewer へ渡す情報 (subagent を使う場合):

- **作業仕様ファイルのパス** — `/tmp/dev-task/<project-basename>/workspec.md` (受け入れ条件・仮定・公開境界の変更宣言を含む)
- **対象レイヤーの reference パス** — `${DEV_TASK_SKILL_DIR}/references/<layer>.md` を絶対パスに展開して、変更が触れたレイヤー分すべて渡す。implementer と同じ基準でレビューさせるため
- **比較ベース** — `git diff HEAD` で見るなら指定なし、`git diff <base>...HEAD` なら base を明示

`reviewer-style` 固有:
- **類似実装パス** — フェーズ 2 で見つけた参照パターン

codex レビュー (併用時): `references/codex-review.md` に従う。Skill から渡すのは比較ベースが既定と異なるときの `--base <ref>` だけ。

### レビュー結果の処理

reviewer の判定 (PASS / NEEDS_REVISION) と、併用した場合の codex 出力をまとめて評価する。codex の指摘は PASS / NEEDS_REVISION 形式とは限らないので、メインが重大度を判定して must / imo 相当に振り分ける:

- **全員 PASS かつ codex に重大指摘なし (併用時)** → フェーズ 7 へ
- **いずれかに NEEDS_REVISION / 重大指摘** → must 相当を反映して修正、フェーズ 5 から再実行
- **再修正後の再レビューは 2 回まで**。2 回目でもまだ未解消の must が残るなら、残差をユーザーに提示して判断を仰ぐ

imo 指摘 (reviewer の imo、codex の軽微指摘) は採用 / 不採用をメインが判断する。不採用にする場合は理由を最終報告に残す。

**UI タスクでレビューの must 指摘により実装が変わった場合は、4e-1 (影響分のみ、Figma 画像は流用) → 4f → 4g を再実行。**

## フェーズ 7: コミット・プッシュ・draft PR 作成と完了報告

ローカルチェック通過 (+ 該当時は reviewer PASS) で実装完了とする。変更を適切な粒度で commit し、push し、**draft PR を作成する**。

**UI タスクの場合**: コミット前に `/tmp/dev-task-visual-check/<project-basename>/` の Playwright スクショと Figma フレーム画像を side-by-side で見せ、ユーザー最終確認を求める。

### 7-1. ブランチ確認

`git branch --show-current` で現在ブランチを確認する。

- **機能ブランチ上 (デフォルトブランチ以外)** → そのまま 7-2 へ (worktree 運用では起動時点で機能ブランチにいるのが通常ケース)
- **デフォルトブランチ上 (`master` / `main` / `develop`)** → 直接コミットせず、`references/git-workflow.md` の手順で機能ブランチ + worktree を自動作成してからコミットする (ブランチ名は `wakwak3125/` プレフィックス + kebab-case slug、未コミット変更は stash で worktree へ持ち越し、以降の commit/push は worktree 内で行う)

### 7-2. コミット

- 論理的にまとまった単位で分割し、無関係な変更を 1 コミットに混ぜない。レイヤーの異なる変更 (proto / backend / frontend) やリファクタと機能追加は別コミットにする。trivial な単一目的の変更は 1 コミットでよい。
- メッセージは conventional commits スタイル (日本語可)。サマリはタスクの意図 (WHY) を表す。Linear チケットがあれば本文にチケット ID を記す。コードと同じく、コミットメッセージにも「今回の修正で」等の冗長表現は入れない。
- 機密ファイル (.env、credentials 等) はコミットに含めない。

### 7-3. プッシュ

現在ブランチを origin に push する。upstream 未設定なら `-u origin <branch>` で設定する。

### 7-4. draft PR 作成

`gh pr create --draft` で draft PR を作成する。

- **タイトル**: 日本語の conventional commits スタイル。タスクの意図 (WHY) を表す。
- **本文**: 概要 (何を / なぜ) と受け入れ条件 (workspec の内容) を簡潔に。Linear チケットがあればチケット ID を記す。テスト・検証結果に触れてよい。冗長表現は入れない。
- base ブランチはデフォルトブランチ (`master` / `main` / `develop`)。`--draft` を必ず付ける。
- 既に同一ブランチの PR が存在する場合は新規作成せず、その URL を報告する。
- PR 作成に失敗した場合 (権限・remote 未設定等) は中断せず、エラー内容を完了報告に含めてユーザーに判断を委ねる。

### 7-5. 完了報告

**結論から書く。** 最初の 1 文で「何をしたか / タスクが完了したか」を述べ、詳細はその後に続ける。ノールックで長く進んだ後の報告ほど、作業中の省略記法や内部用語を持ち込まず初見の読者向けに書き直す。

各項目は、このセッションの tool 結果で裏が取れるものだけを断定する。未検証・スキップ・失敗はそのまま書く。含める内容:

- 最終結果 (完了 / ブロック)
- 担当宣言 (メイン / 実装 subagent とその理由)
- 検証結果 (型/ビルド/テスト/lint の pass/fail。実際に実行したものだけ)
- codex レビュー併用の有無 (スキップした場合はその理由)
- 作成したコミット、push 先ブランチ (worktree を作った場合はそのパス)
- 作成した draft PR の URL (失敗時はエラー内容)

## References

言語別 (フェーズ 4 で参照):

- `references/kotlin.md`
- `references/react-ts.md`
- `references/nodejs.md`
- `references/protobuf.md`

UI (フェーズ 4a〜4g で参照):

- `references/figma-extraction.md` — Figma MCP の呼び出し、取得すべきもの、検証用フレーム画像の命名規約
- `references/design-system-discovery.md` — primitive 探索の戦略
- `references/token-map-inference.md` — Figma 変数とコードトークンの突合
- `references/storybook-verification.md` — Story 用意基準、Storybook + Playwright ループ、ペアチェック、機械 diff、比較の心得

ワークフロー (フェーズ 6〜7 で参照):

- `references/runtime-claude-code.md` — Claude Code でのプラン作成 / Agent / reviewer / Skill ディレクトリ解決
- `references/runtime-codex.md` — Codex でのプラン作成 / main-agent 実装 / self-review / Skill ディレクトリ解決
- `references/codex-review.md` — Claude Code 実行時に codex レビューを併用する場合の使い分け・companion 起動方法・fallback
- `references/git-workflow.md` — デフォルトブランチ上での機能ブランチ + worktree 自動作成手順

## Scripts

- `scripts/screenshot-stories.mjs` — story を複数の state/ビューポートで撮る Playwright スクリプト。Skill 配下にインストールされた `playwright` を使うため、複数プロジェクトをゼロコンフィグで横断する。`${DEV_TASK_SKILL_DIR}` 経由で呼ぶ。
- `scripts/diff-pairs.mjs` — `__playwright.png` / `__figma.png` ペアを pixelmatch で機械比較し、差分ハイライト画像 (`__diff.png`) と diff 率サマリを生成する (フェーズ 4f)。
- `package.json` — Skill 自身が抱える依存 (playwright / pixelmatch / pngjs) の宣言。初回 `npm install` 用 (UI タスク時のみ)。
