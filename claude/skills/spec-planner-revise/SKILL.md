---
name: spec-planner-revise
description: spec-planner-plan で作成済みの設計成果物（design.md / data-model.md / requirements-mapping.md / usecases.md / open-issues.md / minutes.md / revision-history.md）を、ユーザーからの修正指示に基づいて改訂する。spec-planner-plan と同じ 5 人 subagent チーム（architect / modeler / analyst / critic / scribe）を基本に、critic の重大指摘が尽きるまで動的にラウンドを回し、既存成果物を直接更新する。改訂議事は `revision-history.md` に集約し、元ファイルには改訂マーカーを残さない。設計変更・仕様修正・未決事項の解決を議論込みで進めたいときに使う。
argument-hint: <修正指示の本文。先頭に対象スラグを `slug: <name>` 形式で指定可（省略時は自動検出）>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskList, TaskUpdate, TaskGet
---

# spec-planner-revise: 既存設計を 5 人チームで改訂するスキル

あなたはこのスキルのファシリテーター（エージェントチームの**リーダー**）として動く。
spec-planner-plan で生成された既存成果物と、ユーザーからの修正指示を入力に、
spec-planner-plan と同じ subagent 構成の agent team を編成し、
2〜5 ラウンドの批判的議論と改訂を経て既存成果物を更新する。

## 入力

`$ARGUMENTS` には以下が含まれる:

- **修正指示**（必須）: 何をどう直したいか。新要件の追加、設計変更、open-issues の解消、モデル再検討、命名変更、など。
- **対象スラグ**（任意、推奨）: `slug: <name>` の形式で先頭に指定。省略時はフェーズ 0-2 で自動検出する。

例:

- `slug: order-cancel 返金フローを外部決済プロバイダ切替に対応させる。冪等性要件を追加。`
- `open-issues の #3 と #5 を解決してほしい。必要ならデータモデルを修正してよい。`
- `ユースケース "在庫戻し" の並行実行に関する制約が曖昧。再検討して design.md を更新。`

---

## フェーズ 0: 事前チェックと準備

### 0-1. Agent Teams が有効かを確認

- 現在の値: !`echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-unset}"`

上記が `unset` または `0` なら、次のように伝えて中断する:

> Agent Teams が無効です。以下のいずれかで有効化してください:
> - `~/.claude/settings.json` に `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}` を追加
> - もしくは現在のシェルで `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` してから Claude Code を再起動

有効なら次へ進む。

### 0-2. 対象ディレクトリの特定

現在の作業ディレクトリ配下の `./spec-planner-output/` を確認し、改訂対象スラグを決める:

1. `$ARGUMENTS` の冒頭に `slug: <name>` があれば最優先で採用。
2. 無ければ `./spec-planner-output/` 配下のディレクトリを列挙:
   - 0 件: 「spec-planner-output が見つからない、または空」とユーザーに伝えて中断。先に `spec-planner-plan` を実行してもらう。
   - 1 件: そのスラグを自動採用し、使用スラグをユーザーに通知。
   - 2 件以上: 各スラグの `design.md` 冒頭 3 行と最終更新日時を一覧で提示し、ユーザーに指定を求めて中断。推測しない。

採用した作業ディレクトリの絶対パスを `<WORKDIR>` として以降で使う（例: `/…/spec-planner-output/<slug>/`）。

### 0-3. 成果物の存在確認

`<WORKDIR>` 配下に以下のファイルが揃っているか確認する:

- `design.md`
- `data-model.md`
- `requirements-mapping.md`
- `usecases.md`
- `open-issues.md`
- `minutes.md`
- `revision-history.md`

欠落があれば、欠けているファイル名をユーザーに報告し「spec-planner-plan のテンプレートから不足ファイルを補ってよいか」を確認してから補完する。無断で補わない。`data-model.md` と `revision-history.md` は新しい運用で追加されたファイルなので、旧スキル版で生成された `<WORKDIR>` では欠落している可能性がある。

### 0-4. 現状スナップショットの把握

リーダー（あなた）は、ラウンド開始前に自分で `<WORKDIR>` の全ファイル（`minutes.md` / `revision-history.md` を含む）を通読し、以下をメモする（ユーザーには出さない、ラウンド運営に使う）:

- 既存の主要な設計判断とその根拠
- 既存のテーブル定義の骨子（主要テーブル名・責務・主キー）
- 現在の open-issues の一覧（番号・重要度・概要）
- 過去の改訂履歴（`revision-history.md`）から読み取れる経緯
- 修正指示が影響を及ぼしそうな範囲（どのファイルのどのセクション）

### 0-5. チーム編成

既定チームは spec-planner-plan と同一の 5 人。subagent 定義は `~/.claude/agents/spec-planner-*.md` を流用する:

| メンバー | subagent 型 | 役割 |
|---------|------------|-----|
| architect | `spec-planner-architect` | 全体設計・モジュール境界 |
| modeler | `spec-planner-modeler` | データモデル・ER図・ユースケース |
| analyst | `spec-planner-requirements-analyst` | 要求分解・対応表 |
| critic | `spec-planner-critic` | 批判的レビュー (devil's advocate) |
| scribe | `spec-planner-scribe` | 議事録・文書整合性 |

**ドメイン別オプション専門家**（対象ドメインに応じて追加）:

| メンバー | subagent 型 | 役割 | 追加条件 |
|---------|------------|-----|---------|
| ehr | `japan-ehr-specialist` | 日本の電子カルテ法令・標準規格・医療DX政策 | 修正指示や既存 design.md に「電子カルテ」「EHR」「診療録」「SS-MIX」「FHIR」「医療情報」「電子処方箋」等が含まれる、または明示指定 |
| receipt | `japan-receipt-computer-specialist` | 日本の診療報酬・レセコン・算定要件・審査実務 | 修正指示や既存 design.md に「レセコン」「診療報酬」「点数算定」「レセプト」「医事」「算定要件」「施設基準」等が含まれる、または明示指定 |

**改訂時の追加判断**: 既存 spec-planner-plan 実行時にドメイン専門家が参加していた痕跡（`minutes.md` に `ehr` / `receipt` 発言あり）がある場合は、今回の改訂でも参加させる。既存判断との整合性を保つため。

`$ARGUMENTS` にチーム構成の追加・除外指定があれば反映する。指定も検出キーワードもなければ 5 人のまま進める。

---

## フェーズ 1: エージェントチーム起動

### 1-1. Team コンテキストを先に作る（必須）

`Agent` を `team_name` 付きで呼ぶ前に、**必ず先に** `TeamCreate` で team コンテキストを作成する。
これを飛ばすと `Not in a team context. Create a team with Teammate spawnTeam first, or set CLAUDE_CODE_TEAM_NAME.` で失敗する。

```
TeamCreate({
  team_name: "spec-planner-revise-<slug>",
  description: "spec-planner-revise: <対象スラグ> の改訂"
})
```

team_name は kebab-case（先頭は英字、英数字とハイフンのみ）。`<slug>` はフェーズ 0-2 と同じ値を使う。
同名 team が既に存在する場合は `-r2`, `-r3` のサフィックスで避ける。

### 1-2. チームメンバーを並列生成

`TeamCreate` 成功後、**同一メッセージ内で**（並列に）0-5 で確定したメンバー数ぶんの `Agent` tool を呼ぶ。各呼び出しには以下を必ず指定する:

- `subagent_type`: 既定 5 人は `spec-planner-architect` / `spec-planner-modeler` / `spec-planner-requirements-analyst` / `spec-planner-critic` / `spec-planner-scribe`。ドメイン専門家は `japan-ehr-specialist` / `japan-receipt-computer-specialist`
- `name`: `architect` / `modeler` / `analyst` / `critic` / `scribe` / `ehr` / `receipt`（SendMessage の宛先になる）
- `team_name`: 1-1 で作成した team_name（**省略厳禁**）
- `description`: 短い役割説明
- `prompt`: 下記の初期プロンプト

ドメイン専門家を追加した場合は、他メンバーへの初期プロンプトにも**専門家の存在と委譲ルール**を明記する（医療系の法令・規格質問は `ehr` に、点数・算定は `receipt` に振る）。

### 1-3. 初期プロンプトに必ず含める項目

1. **モードの明示**: 「これは新規設計ではなく**既存設計の改訂**である」「既存の判断と根拠を尊重し、変更する場合は理由を `revision-history.md` に残す」
2. **ユーザーからの修正指示**（$ARGUMENTS から slug 指定部分を除いた本文全文）
3. **作業ディレクトリの絶対パス**: `<WORKDIR>`
4. **役割別必読ファイル**（全員全読みはしない。下記に限定）:
   - architect: `design.md` / `requirements-mapping.md` / `open-issues.md` / `revision-history.md`
   - modeler: `data-model.md` / `usecases.md` / `design.md` の該当節 / `open-issues.md`
   - analyst: `requirements-mapping.md` / 修正指示本文 / `open-issues.md`
   - critic: リーダーから broadcast される既存設計要旨と改訂差分サマリ + `open-issues.md` + `revision-history.md`
   - scribe: 全ファイル（整合チェック担当。`minutes.md` は読むが書かない）
   - ehr / receipt: 自分に振られた質問文と、その質問が指す成果物の該当節のみ

   2 ラウンド目以降はリーダーが broadcast する「差分サマリ」のみで進め、他ファイルは必要時にだけ Read する。
5. **team_name**（他メンバーへの SendMessage で使用）と**自分の name**、**他メンバーの name 一覧**
6. **各ファイルの役割**:
   - `design.md`: 設計判断・アーキテクチャ・非機能要件への対応
   - `data-model.md`: テーブル定義と ER 図の一次情報（改訂時もスキーマの実体はここに書く）
   - `requirements-mapping.md`: 要求 ↔ 設計の対応表
   - `usecases.md`: ユースケースごとの入出力・状態遷移
   - `open-issues.md`: 未決事項
   - `minutes.md`: **初回設計時の議事録。本スキルでは一切触らない**
   - `revision-history.md`: **本スキルが追記する唯一の議事系ファイル**。`## Revision R{N} (<日付>)` 見出しで末尾追記
7. **設計原則**（spec-planner-plan と共通、必ず転記）:
   - 要求を満たす最小の設計を第一候補とする
   - ただしシンプルすぎて負債が溜まる設計は却下する
   - 判断は常に「なぜ」とセットで残す
   - 他メンバーに対して合理的かつ厳しく批判する
   - 合意なき妥協をしない。反駁されたら認める
8. **文書品質原則**（必ず転記、既存記述の書き換え時・新規追記時ともに厳守）:
   - **読み手はこのシステムを既に知る熟練エンジニア**。背景説明・用語定義・一般論は書かない
   - **箇条書きは本当に列挙可能な離散項目のみ**。設計判断の理由・経緯・トレードオフは**散文**で書く
   - **採用した決定と、却下した代替案を却下理由とともに書く**。両論併記やトレードオフの羅列は禁止
   - **抽象語単独禁止**。「スケーラブル」「堅牢」等は、具体的な数値・メカニズム・具体例を添えなければ書かない
   - 既存文書を改訂する際、明らかに冗長な既存箇所も併せて削減してよい（ただしスコープ外の大規模書換は合意後）。最終整合で scribe が「30% 削減・情報密度向上」パスを行う（フェーズ 3 で実施）
9. **改訂時の追加原則**:
   - 既存設計を**不必要に広範囲には変更しない**（修正指示のスコープを逸脱する変更は提案止まりにして open-issues に登録）
   - 変更は**差分が追える形**で行う（該当セクションだけを更新、章構成の大幅再編は合意後）
   - **元ファイルに `v2` / `rev2` / `（改訂）` 等の改訂マーカーを残さない**。設計ドキュメントは常に「最新の確定版」として書く。履歴は `revision-history.md` のみに集約
   - 改訂議事は `revision-history.md` に `## Revision R{N} (<日付>)` 見出しで末尾追記する。`minutes.md` は一切触らない
   - 過去の改訂で記録された判断と矛盾する変更を入れる場合は、`revision-history.md` を遡って確認し、矛盾理由を今回の Revision セクションに明記する
10. **ラウンド制**: ラウンド数は**固定しない**。critic の重大指摘が尽きるまで継続。各ラウンドの目的はリーダー（=あなた）が宣言する
11. **対話の自由**: メンバー同士は SendMessage で直接対話してよい（宛先は name）

## フェーズ 2: 改訂ラウンド進行

**ラウンド数は固定しない**。critic（およびドメイン専門家が参加している場合はその専門家）の**重大指摘が尽きるまで**継続する。最低 1 ラウンドは必ず実施する。

**各ラウンドの最低構成**:

1. リーダーがラウンド番号と目的、**前ラウンドからの差分サマリ**をチームに broadcast（2 ラウンド目以降）
2. analyst が修正指示を要求分解して影響範囲を整理、architect / modeler に検討依頼
3. 担当メンバーが既存成果物の該当セクションに対する改訂案を作る。**独立な作業はリーダーが同一メッセージで並列 SendMessage し、逐次にしない**
4. critic が批判的論点を提起（特に「この変更で壊れる既存要求はないか」「open-issues と矛盾しないか」を必ず含める。ゼロ提起はリーダーが観点を指示して再検討させる）
5. 全論点が解消（または open-issues 行き）するまで対話
6. scribe が `revision-history.md` の当該 Revision セクションに追記（論点→結論の形式）し、`requirements-mapping.md` / `design.md` / `data-model.md` / `usecases.md` / `open-issues.md` の整合を確認。`minutes.md` には触らない
7. リーダーが次ラウンドの要否を判断:
   - **継続**: critic が新たな重大論点を提起した / 未解消の論点が残っている / 新たな影響範囲が発覚した
   - **終了**: critic が「重大な指摘なし」と明示合意し、修正指示の各項目が全て反映済み、既存要求・open-issues との整合に問題なし

**ラウンド目的のガイド**（リーダーが各ラウンド冒頭で宣言する。典型例で、対象に応じて調整）:

- 修正指示の要求分解、影響範囲の特定、改訂方針の合意（analyst + architect）
- 改訂方針に従ったドラフト反映（modeler + architect）
- critic による回帰レビュー、既存要求・open-issues との整合チェック（critic + analyst）
- 指摘の反映と requirements-mapping / open-issues の更新（analyst + scribe）
- 最終整合・用語統一・`revision-history.md` への総括追記（scribe + 全員）

**暴走防止**: 同一論点で 2 ラウンド連続して合意に至らない場合、その論点は `open-issues.md` に「未決」で移し、次ラウンドでは別論点に進む。リーダーが 5 ラウンドを超えそうと判断した時点でユーザーに中間報告し、継続可否を確認する（改訂は局所変更が前提なので、長引く場合はスコープ膨張の可能性が高い）。

### ラウンド間で必ず確認

- [ ] 修正指示の各項目が **どのファイルのどのセクションに**反映されたか説明できる
- [ ] `requirements-mapping.md` に追加/変更された要求の対応が記載されている
- [ ] `open-issues.md` に今回の改訂で解消した項目は **解消理由と共に close 扱い**で残っているか（黙って消さない）
- [ ] `design.md` / `data-model.md` / `usecases.md` の変更が `revision-history.md` の当該 Revision セクションに紐づくか
- [ ] 元ファイルに `v2` / `rev2` / `（改訂）` 等の改訂マーカーが紛れ込んでいないか
- [ ] `minutes.md` が無改変のまま維持されているか
- [ ] 用語・ID・テーブル名・参照が変更前後で崩れていないか（scribe にチェックさせる）

## フェーズ 3: 最終統合

最終ラウンド後、scribe に以下を**順に**依頼:

1. **整合チェック**: 全成果物を通読し、**変更箇所と既存記述の境目**で矛盾・用語ゆれ・参照切れ・改訂マーカー混入（`v2` / `rev2` / `（改訂）` 等）が発生していないか最終チェック
2. **30% 削減パス**: 今回改訂した箇所を中心に、`design.md` / `usecases.md` / `requirements-mapping.md` の**情報密度を上げて最低 30% 行数を削減する**（`data-model.md` は簡潔志向なので重複整理程度）。対象は改訂箇所が原則。明らかに重複する既存箇所も削減してよいが、スコープ外の大規模書換は `revision-history.md` の「見送り提案」にとどめる。具体的には:
   - 同じ内容を別の言い方で書いている箇所を統合する
   - 自明な説明・冗長な前置き・目次の水増しを削除する
   - 箇条書きを散文に書き換える（本当に列挙可能な離散項目は残す）
   - 抽象語単独の記述は、具体化するか削除する
   - 両論併記は採用決定＋却下理由の形に書き換える
3. **冒頭整備**: `design.md` 冒頭の「目的とスコープ」を、今回の改訂結果を反映し、**既にシステムを知る熟練エンジニア**を読み手と想定した最短表現に整える（大幅変更がなければ触らない）
4. **改訂まとめ**: `revision-history.md` の当該 Revision セクション末尾に「改訂まとめ」を追記: 改訂指示の要約 / 合意した主要変更（ファイル別） / 見送った提案と理由 / 新規 open-issues。`minutes.md` は触らない
5. **未決整理**: `open-issues.md` を重要度順にソートし直し、新規追加項目には放置した場合の影響を記載

仕上がりの文書品質基準（scribe に厳守させる）:

- **読み手はこのシステムを既に知る熟練エンジニア**。背景説明・用語定義・一般論は書かない
- 箇条書きは列挙可能な離散項目のみ。設計判断の理由・経緯は散文
- 決定とその却下理由のみ記述。両論併記・トレードオフの羅列は禁止
- 「スケーラブル」「堅牢」等の抽象語は必ず数値・メカニズム・具体例を伴う
- 改訂前後で**論理順が崩れていない**
- 「目的 → 前提 → 結論 → 根拠 → 詳細 → 未決事項」の論理順
- 記述は最小、情報量は最大（冗長な前置き・自明な説明・目次の水増しなし）

## フェーズ 4: クリーンアップと報告

1. 各メンバーに `SendMessage({to: "<name>", message: {type: "shutdown_request"}})` でシャットダウンを依頼
2. 全員のアイドル/停止を確認したら `TeamDelete` を呼んで team リソースを削除
   - `TeamDelete` はアクティブメンバーが残っているとエラーになる。その場合は再度シャットダウンを送る
3. ユーザーに以下を報告:
   - 作業ディレクトリの絶対パス
   - 実行ラウンド数
   - 変更したファイルと、それぞれで更新されたセクション見出し
   - 解消した open-issues 件数 / 新規 open-issues 件数
   - 見送った提案（あれば）を 3 件以内
   - 特に注目すべき判断・論点を 3 件以内

---

## 運営上の厳守事項

- **合意なき妥協をしない**: 議論ポイントは解消まで続ける。解消できないものは `open-issues.md` に明示（放置しない）。
- **沈黙を許さない**: critic が 1 ラウンドで新しい指摘ゼロなら、リーダーが観点を指示して再検討させる。
- **既存記述を破壊しない**: 改訂は差分で行う。大規模な書き換えが必要と判断した場合は、合意後に scribe が実施する。
- **スコープクリープ防止**: 修正指示と無関係な改善は、その場で適用せず `open-issues.md` に提案として積む。
- **成果物は毎ラウンド更新**: 議論だけで終わらせない。ファイルに反映させて初めてそのラウンドを閉じる。
- **並列性を活かす**: 独立な作業指示は**同一メッセージで複数 SendMessage** を並べる。逐次化はトークンと壁時間の無駄。
- **ファイル読みは最小限**: 各メンバーは主担当ファイル以外を毎ラウンド読まない。リーダーの差分サマリで足りるよう運営する。
- **ユーザーには中間報告を最小限に**: 各ラウンド完了時に 1〜2 行のサマリだけ出す。詳細はすべてファイルに。
- **$ARGUMENTS の修正指示が曖昧な場合**: 即座に止めて、何を・なぜ・どこまで変えたいのかを問う。推測で進めない。

## 参照

- [Agent Teams docs](https://code.claude.com/docs/ja/agent-teams)
- subagent 定義: `~/.claude/agents/spec-planner-*.md`
- 初回設計スキル: `~/.claude/skills/spec-planner-plan/SKILL.md`
- テンプレート（欠損補完用）: `~/.claude/skills/spec-planner-plan/templates/`
