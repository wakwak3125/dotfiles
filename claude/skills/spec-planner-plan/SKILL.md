---
name: spec-planner-plan
description: 要求仕様を入力として、architect / modeler / requirements-analyst / critic / scribe の単発 subagent を逐次呼び出して高度なソフトウェア設計レビュー＆改訂を行う。critic 3 段階（軽量 2 回 + 最終 1 回）で blocker ゼロまで needs-revise ループを回す。成果物は設計書（design.md）・データモデル（data-model.md：ER図＋テーブル定義）・要求対応表・ユースケースごとのデータ構造・残タスク・議事録・改訂履歴・critic 指摘簿・作業状態。設計の検討・設計レビュー・仕様策定の議論を深めたいときに使う。
argument-hint: <設計対象のコンテキストと任意のチーム構成>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, TaskCreate, TaskList, TaskUpdate, TaskGet
---

# spec-planner-plan: 要求 → 設計 を単発 subagent の逐次フローで鍛えるスキル

あなたはこのスキルのファシリテーター（**オーケストレーター**）として動く。
入力から設計対象を読み取り、subagent 定義に基づく**単発 `Agent` 呼び出し**を逐次発火し、
critic の blocker 指摘が尽きるまで needs-revise ループを回して成果物を仕上げる。

**Agent-Team は使わない**。`TeamCreate` / `SendMessage` / `TeamDelete` は呼ばない。各 subagent は使い捨てで、1 回の呼び出しごとにファイルへ成果物を吐き出し、メインへは 1 行サマリだけ返す。状態は `task-state.md` / `critic-findings.md` に永続化し、メインのコンテキストに議論を溜めない。

## このスキルが Opus 4.7 で動く前提

Opus 4.7 は (a) 既定で subagent を控えめに spawn し、(b) tool 呼び出しよりも推論を優先し、(c) effort レベルに厳密に従い、(d) 指示を字義通りに解釈する。本スキルはこの傾向と整合させた設計になっている:

- **単発 subagent 逐次フローは Opus 4.7 と相性が良い**: 前ステップの成果物が次ステップの入力になるドメインで並列 fan-out は不要。subagent 1 体ごとに独立成果物を 1 ファイル吐かせることで、メインのコンテキストと判断負荷を最小化する。fan-out は明示的に有効な箇所（ステップ 6.5 のドメイン専門家複数）でのみ行う
- **指示は字義通り**: 「同様に」「適切に」「自動的に」「必要に応じて」等の曖昧語を prompt に書かない。何を / どのファイルの / どのセクションに / どんな形式で書くかを毎回明示する。Opus 4.7 は推測で補完しない
- **思考深度は prompt で steer する**: 深い設計判断（architect / 最終 critic）は **「Think carefully step-by-step. 設計判断のひとつひとつが下流に波及する」** を必ず入れる。定型作業（analyst の要求分解、modeler の正規化適用、scribe の整合修正）は **「Respond directly. 過剰な熟考は不要」** を入れる
- **tool 呼び出しは推論より控えめが既定**: 各 subagent には「読むべきセクションは offset/limit で必要箇所のみ。Grep は cross-file 整合性の確認用途に限る」と毎回書く。爆発的な Read を促す指示（「全体を把握して」）は禁止
- **進捗ナレーションは control する**: Opus 4.7 は agentic trace 中に適切な間隔で進捗を自発的に返す。メインは各ステップ完了後に `task-state.md` 更新 + 1 行報告だけに留め、"now I will..." 系のナレーションは出さない
- **コンテキスト前出し**: 各 subagent には 1 ターンで完結する全情報（タスク意図 / 制約 / 受け入れ基準 / 対象ファイルとセクション / 許可された Read 範囲 / 成果物フォーマット）を初回 prompt に揃える。後追いの「追加で◯◯も」は出さない

## 入力

`$ARGUMENTS` には以下が含まれる:
- **何についての設計か**（必須）: 対象システム・機能の説明、既存コード参照、要求仕様の要点
- **チーム構成**（任意）: 追加したい専門家（ehr / receipt 等）、除外したいメンバー、特別な指示

例:
- `ECサイトの注文キャンセル機能の設計。返金フローと在庫戻しも含む。`
- `マルチテナント課金基盤。デフォルトに加えて security-expert 視点を critic に強めに入れる。`

---

## フェーズ 0: 事前チェックと準備

### 0-1. 作業ディレクトリの準備

対象に短いスラグ（kebab-case、英数字）を付与し、`./spec-planner-output/<slug>/` を作成する。既存なら `-v2`, `-v3` で避ける。

テンプレートをコピーして初期化する:

```
cp ~/.claude/skills/spec-planner-plan/templates/design.md               ./spec-planner-output/<slug>/design.md
cp ~/.claude/skills/spec-planner-plan/templates/data-model.md           ./spec-planner-output/<slug>/data-model.md
cp ~/.claude/skills/spec-planner-plan/templates/requirements-mapping.md ./spec-planner-output/<slug>/requirements-mapping.md
cp ~/.claude/skills/spec-planner-plan/templates/usecases.md             ./spec-planner-output/<slug>/usecases.md
cp ~/.claude/skills/spec-planner-plan/templates/open-issues.md          ./spec-planner-output/<slug>/open-issues.md
cp ~/.claude/skills/spec-planner-plan/templates/minutes.md              ./spec-planner-output/<slug>/minutes.md
cp ~/.claude/skills/spec-planner-plan/templates/revision-history.md     ./spec-planner-output/<slug>/revision-history.md
cp ~/.claude/skills/spec-planner-plan/templates/critic-findings.md      ./spec-planner-output/<slug>/critic-findings.md
cp ~/.claude/skills/spec-planner-plan/templates/task-state.md           ./spec-planner-output/<slug>/task-state.md
```

- `data-model.md`: テーブル定義と ER 図の一次情報
- `design.md`: 設計判断のみ（`{TITLE}` をこの段階で差し替え）
- `revision-history.md`: 初期は空のまま（`spec-planner-revise` が使用）
- `critic-findings.md`: critic 指摘の表形式簿。needs-revise ループの一次情報
- `task-state.md`: 現在フェーズ・次アクション・blocker 残数。compaction 耐性のための最小状態

作業ディレクトリの絶対パスをユーザーに 1 行で通知する。

### 0-2. subagent 編成

既定は次の 5 役（subagent 定義は `~/.claude/agents/spec-planner-*.md`）。このスキルでは**常駐させず、必要なステップで 1 回だけ単発 `Agent` として呼ぶ**。

| 役 | subagent_type | 担当ファイル / 役割 |
|---|---|---|
| analyst | `spec-planner-requirements-analyst` | `requirements-mapping.md`（要求分解・対応表） |
| architect | `spec-planner-architect` | `design.md` / `open-issues.md`（全体設計・モジュール境界） |
| modeler | `spec-planner-modeler` | `data-model.md` / `usecases.md`（テーブル・ER・ユースケース） |
| critic | `spec-planner-critic` | `critic-findings.md`（批判的レビュー。本文は書かず指摘行のみ追記） |
| scribe | `spec-planner-scribe` | 最終統合時のみ起動。全ファイルの整合・削減・冒頭整備・議事総括 |

**ドメイン別オプション専門家**（`$ARGUMENTS` 検出または明示指定で追加）:

| 役 | subagent_type | 追加条件 |
|---|---|---|
| ehr | `japan-ehr-specialist` | 「電子カルテ」「EHR」「診療録」「SS-MIX」「FHIR」「医療情報」「電子処方箋」「PHR」等を検出、または明示指定 |
| receipt | `japan-receipt-computer-specialist` | 「レセコン」「診療報酬」「点数算定」「レセプト」「医事」「算定要件」「施設基準」等を検出、または明示指定 |

医療ドメインでは法令・規格は ehr、点数・算定は receipt の委譲ルールで役割が分かれる。両方同時に呼ぶことが多い。最終 critic の後に 1 往復だけドメインチェックを挟む（ステップ 6.5）。

---

## フェーズ 1: 単発 subagent の呼び出し契約

すべての subagent 呼び出しは**単発 `Agent` tool**で行う。毎回必ず以下を守る。

### 呼び出し時

- `subagent_type`: 上表のいずれか
- `description`: 3〜5 語の動作説明（例: "architect: design.md initial draft"）
- `prompt`: 下記「prompt に毎回含める項目」を全件充足すること。本質的に不要なコンテキストは渡さない
- 並列化は**しない**（このスキルは逐次が前提）。例外はステップ 6.5 のドメイン専門家複数。逐次が必要なのは前ステップ成果物が次の入力になるため
- `model`: 役割ごとに明示指定する（agent 定義側の `model: inherit` を上書き）。Opus 4.7 は effort を厳密に守るため、深い判断が要る役は必ず Opus、定型作業は Sonnet に倒す:
  - **`"opus"`**: architect（ステップ 2 / 7）、最終 critic（ステップ 6）。設計判断の波及範囲が広く、字義通り解釈の精度・批判の深度ともに Opus が必要
  - **`"sonnet"`**: analyst（ステップ 1 / 7）、modeler（ステップ 4 / 7）、軽量 critic（ステップ 3 / 5）、scribe（ステップ 8）、ehr / receipt（ステップ 6.5）。要求分解・正規化・整合修正・規格チェックは Sonnet で十分
  - どちらか迷ったら Sonnet を先に試す。当該ステップで blocker が多発する場合だけ Opus に上げる

### prompt に毎回含める項目（10 件すべて必須・順序は守る）

1. **モード宣言**: 「単発実行。このセッション内で完結させる。作業後に ~200 tokens のサマリだけ返す」
2. **思考深度の cue**:
   - 深い判断が要る役（architect / 最終 critic / 軽量 critic）: 「**Think carefully and step-by-step.** 設計判断のひとつひとつが下流に波及する。代替案を 1 つ以上検討してから採用判断を書け」
   - 定型作業の役（analyst / modeler / scribe / ehr / receipt）: 「**Respond directly.** 既知の手順を適用するだけの作業。過剰な熟考はしない」
3. **作業ディレクトリ絶対パス**: `./spec-planner-output/<slug>/` を絶対パス化したもの
4. **今回の担当範囲**: 対象ファイルと対象セクション。「全体書き換え」「他のファイルも見て調整」は禁止
5. **読んでよいファイル**: 当該 subagent の担当ファイル + `task-state.md` + 直前ステップの成果物（明示列挙）。**全文 Read は禁止。必要なセクションのみ offset/limit で Read**。Grep は cross-file ID/用語整合性の検証用途のみ
6. **書くべき成果物**: どのファイルのどのセクションを Write/Edit するか具体指示。新規見出しを増やしてよい / 駄目を明示
7. **受け入れ基準**（done の定義。ここを満たさない戻り値は不合格として再依頼する根拠）:
   - 担当ファイルに**該当セクションが具体的内容で書かれている**（プレースホルダのまま放置していない）
   - 設計判断には**採用理由と却下した代替案 1 つ以上**が併記されている（critic を除く）
   - critic の場合は**最低 3 件の指摘**を表形式で追記し、severity タグが全件付与されている
   - 戻り値が下記フォーマットに一致する
8. **戻り値フォーマット**（厳守）:
   ```
   wrote: <相対パス>[, <相対パス>...]
   summary: <1 行・80 文字以内>
   findings_count: <critic のみ。blocker=N major=M minor=K の形式>
   ```
   議論文・根拠説明・代替案列挙をメインに返さない。詳細はファイルに書く
9. **設計原則**（必ず転記）:
   - 要求を満たす最小の設計を第一候補とする
   - ただしシンプルすぎて負債が溜まる設計は却下する
   - 判断は常に「なぜ」とセットで残す
   - 他メンバーの成果物は合理的かつ厳しく批判する（critic のみ）
   - 合意なき妥協をしない。反駁されたら認める
10. **文書品質原則**（必ず転記、成果物を書くときに厳守）:
    - **読み手はこのシステムを既に知る熟練エンジニア**。背景説明・用語定義・一般論は書かない
    - **箇条書きは本当に列挙可能な離散項目のみ**。設計判断の理由・経緯・トレードオフは**散文**で書く
    - **採用した決定と、却下した代替案を却下理由とともに書く**。両論併記やトレードオフの羅列は禁止
    - **抽象語単独禁止**。「スケーラブル」「堅牢」「高性能」等は、具体的な数値・メカニズム・具体例を添えなければ書かない
    - 初稿完成後に scribe が「30% 削減・情報密度向上」パスを行う（ステップ 8）

### critic 専用の追加契約

- 議論文・根拠文をメインに返さない。`critic-findings.md` に表形式で追記する
- 各指摘に `severity = blocker | major | minor` を必ず付ける
- `blocker` は「要求未充足・整合性崩壊・データ損失・法令違反など、採用不可級の欠陥」に限定する
- 戻り値の `findings_count` は当該ラウンドで追加した件数。以前のラウンド分は含めない
- 「沈黙＝合格」を許さない。観点が思いつかない場合でも障害シナリオ・並行性・運用・回帰の各軸から最低 1 件は出す（軽量 critic は最大 15 件）

---

## フェーズ 2: 逐次フロー（needs-revise ループ込み）

各ステップ完了時にメインは `task-state.md` の `Current Phase` / `Next Action` / `Completed Steps` を 1 回 Edit し、ユーザーには 1 行報告だけ返す（Opus 4.7 は agentic trace で適切に進捗を出すため、scaffolding は不要）。

### ステップ 1: analyst（単発・Sonnet・直接的）

- 目的: `requirements-mapping.md` 初版。要求分解と未対応要求の洗い出し
- prompt 固有事項: `$ARGUMENTS` の要求本文全文 + 作業ディレクトリ + 思考深度 cue「Respond directly」
- 受け入れ基準: 各要求行に ID / 受入条件 / 担当ファイル予定が埋まっている。未対応要求は別表で列挙

### ステップ 2: architect（単発・Opus・熟考）

- 目的: `design.md` / `open-issues.md` 初版。モジュール境界・主要設計判断
- prompt 固有事項: `requirements-mapping.md` は Read 可（offset/limit）。`design.md` 本文を Write。思考深度 cue「Think carefully and step-by-step」
- 受け入れ基準: 主要設計判断 3 件以上が「採用 + 却下案 + 却下理由」の形で散文で書かれている。`open-issues.md` に 1 件以上の未決事項

### ステップ 3: 軽量 critic 1（単発・Sonnet・熟考）

- 目的: architect 成果物への 1 往復レビュー。**design.md / open-issues.md のみが対象**
- prompt 固有事項: 「軽量レビュー（1 往復・最大 15 件）。severity タグ必須。blocker は要求未充足・整合性崩壊級のみ。Think carefully — 沈黙は劣化」
- 書き込み: `critic-findings.md` の `## Round 1 (preliminary-architect)` セクション
- 受け入れ基準: 最低 3 件の指摘。各 severity タグ付き。findings_count を返す

**needs-revise ゲート**:
- `blocker == 0` → ステップ 4 へ
- `blocker > 0` → architect を再度単発呼び出し。prompt に「`critic-findings.md` の `## Round 1 (preliminary-architect)` の blocker 行のみ対応し、当該行を resolved に書き換える。major/minor は今回触らない。design.md の該当セクションを Edit」を明示。再度このステップ 3 へ戻り、critic は同じラウンドに `## Round 1 (preliminary-architect, retry N)` 見出しで再評価。blocker ゼロまで最大 2 回リトライ。それでも残る場合はユーザーに中間報告して継続可否を問う

### ステップ 4: modeler（単発・Sonnet・直接的）

- 目的: `data-model.md` / `usecases.md` 初版。ER 図・テーブル定義・ユースケースの入出力と状態遷移
- prompt 固有事項: `design.md` の該当節と `requirements-mapping.md` を offset/limit で Read 可。思考深度 cue「Respond directly。正規化と状態遷移の標準手順を適用する作業」
- 受け入れ基準: 全テーブルに PK / 主要 FK / 制約が記載。各ユースケースに入力・出力・状態遷移が記載

### ステップ 5: 軽量 critic 2（単発・Sonnet・熟考）

- 目的: modeler 成果物への 1 往復レビュー。**data-model.md / usecases.md のみが対象**
- prompt 固有事項: 思考深度 cue「Think carefully — 並行競合・整合性・参照整合の観点で深掘り」
- 書き込み: `critic-findings.md` の `## Round 2 (preliminary-modeler)` セクション
- needs-revise ゲート: ステップ 3 と同じ仕組み。blocker > 0 なら modeler を再呼び出し、最大 2 リトライ

### ステップ 6: 最終 critic（単発・Opus・厚めに熟考）

- 目的: 全成果物を横断した最終レビュー。blocker / major / minor を洗い出し
- prompt 固有事項: 「**Think carefully and step-by-step.** 厚めレビュー。全成果物を offset/limit で必要部分だけ Read。Grep で要求 ID と設計記述・テーブル名・カラム名の cross-file 整合性を検証。要求網羅・整合性・非機能・障害シナリオ・運用観点・回帰リスクの 6 軸を一通り。severity タグ必須」
- 書き込み: `critic-findings.md` の `## Round 3 (final)` セクション
- 受け入れ基準: 6 軸それぞれに最低 1 件の検討記録（指摘なしでも「観点 X: 問題なし」を 1 行）

### ステップ 6.5: ドメイン専門家チェック（条件付き・単発・Sonnet）

- 条件: ehr / receipt を 0-2 で追加している場合のみ
- 目的: 法令・規格・点数・算定観点での最終確認（1 往復）
- **fan-out 例外**: ehr と receipt の両方を呼ぶ場合は逐次ではなく**並列**で発火してよい（互いの成果物に依存しないため）
- 書き込み: 指摘は `critic-findings.md` に `## Round 3.5 (domain-ehr)` / `(domain-receipt)` セクションで追記。severity タグは同じ基準
- blocker が増えた場合は次の needs-revise ループ（ステップ 7）に合流

### ステップ 7: needs-revise ループ

最終 critic（+ ドメイン専門家）が出した blocker を、ファイル担当者に配分して解消する:

- `design.md` / `open-issues.md` の blocker → architect を単発呼び出し（対象セクションと `critic-findings.md` の該当行を prompt に明示、該当行のみ resolved に更新させる）
- `data-model.md` / `usecases.md` の blocker → modeler を単発呼び出し
- `requirements-mapping.md` の blocker → analyst を単発呼び出し
- 複数ファイルに跨る blocker は、ファイルごとに分けて該当担当者を順に呼ぶ

全 blocker の status を `resolved` にしたら、再度**最終 critic を単発呼び出し**して残存 blocker を確認（`## Round 3 (final, retry N)`）。blocker ゼロが確認できるまで繰り返す。

- `major` / `minor` は今ループでは触らない。scribe の最終統合（ステップ 8）でまとめて処理させる（体裁・冗長は minor、設計品質の軽微な改善は major として対応）
- 同じ論点で 2 ループ連続して blocker ゼロに至らない場合は、その指摘を `deferred` にして `open-issues.md` に移送（理由と影響を明記）し、当該ループを閉じる
- 8 ループを超えそうと判断した時点でユーザーに中間報告し、継続可否を確認

### ステップ 8: scribe（単発・Sonnet・直接的）

blocker ゼロ確定後に 1 回だけ起動する。prompt 冒頭に思考深度 cue「Respond directly. 整合修正・削減・追記の機械的適用が中心」を入れたうえで、以下を順に指示:

1. **整合チェック**: 全成果物を offset/limit で走査 + Grep で用語・ID・テーブル名・カラム名・参照の一致を検証。不整合は直接 Edit で直す
2. **30% 削減パス**: `design.md` / `usecases.md` / `requirements-mapping.md` の情報密度を上げて最低 30% 行数削減:
   - 同じ内容を別の言い方で書いている箇所を統合
   - 自明な説明・冗長な前置き・目次の水増しを削除
   - 箇条書きを散文に書き換え（本当に列挙可能な離散項目は残す）
   - 抽象語単独の記述は具体化するか削除
   - 両論併記は採用決定＋却下理由の形に書き換える
   - `data-model.md` はもともと簡潔志向。重複整理程度
3. **冒頭整備**: `design.md` 冒頭「目的とスコープ」を、既にシステムを知る熟練エンジニア向けに最短化。背景説明は書かない
4. **critic-findings の major/minor 反映**: `critic-findings.md` の major/minor 指摘のうち採用するものを各ファイルに反映し、status を `resolved` に更新
5. **議事録作成**: `minutes.md` に各ラウンドの論点→結論を簡潔追記（逐語は不要。critic-findings の要約と needs-revise ループの結論を中心に）
6. **未決整理**: `open-issues.md` を重要度順にソートし、全項目に「放置した場合の影響」を記載

scribe の戻り値も `wrote: ..., summary: ...` 形式で 200 tokens 以内。

## フェーズ 3: 報告

scribe 完了後、ユーザーに以下を 1 メッセージで報告:

- 作業ディレクトリの絶対パス
- 実行した needs-revise ループ回数（ステップ 7 のループ回数）
- 成果物（design.md / data-model.md / requirements-mapping.md / usecases.md / open-issues.md / minutes.md）それぞれの行数
- `open-issues.md` の未決件数、`critic-findings.md` で `deferred` に回った件数
- 特に注目すべき判断・論点を 3 件以内

---

## 運営上の厳守事項

- **戻り値最小化**: 各 subagent の戻り値は `wrote: / summary: / findings_count:` 形式で最大 200 tokens。議論文・根拠・代替案をメインに返させない。詳細はすべてファイルに書く
- **ファイル全文 Read 禁止**: メインも subagent も、必要なセクションだけ offset/limit で Read する。Grep は cross-file 整合の検証用途。全文通読が必要なのは scribe の整合チェック時のみ
- **Agent-Team を使わない**: `TeamCreate` / `SendMessage` / `TeamDelete` を呼ばない。subagent は毎回新規 `Agent` 呼び出しで使い捨て
- **状態はファイルに**: ラウンド番号・blocker 残数・次アクションは `task-state.md` / `critic-findings.md` に書く。メインのコンテキストに累積させない
- **needs-revise は blocker ゼロで閉じる**: major/minor の残存は scribe 最終統合で処理。最終 critic で blocker ゼロを明示確認してからステップ 8 へ進む
- **沈黙を許さない**: critic の `findings_count` が `blocker=0 major=0 minor=0` の場合は、prompt に観点（例: 障害シナリオ・非機能・運用）を具体的に指示して 1 回だけ再依頼する。それでも沈黙なら「重大な指摘なし」として確定
- **暴走防止**: 同一指摘で 2 ループ連続解消しない場合は `deferred` → `open-issues.md` 行き。8 ループ超えそうならユーザー確認
- **字義通り解釈の徹底**: prompt に「同様に」「適切に」「自動的に」「必要に応じて」を書かない。Opus 4.7 は曖昧語を補完しない。受け入れ基準を満たさない戻り値は再依頼する
- **メインのナレーション抑制**: ステップ間の "now I will..." 系の前置きを書かない。Opus 4.7 は agentic trace で自然に進捗を返す
- **$ARGUMENTS に要求仕様の本文が薄い場合**: 即座に止めて、具体の要求を問う。推測で進めない

## 参照

- subagent 定義（変更なし・読み取りのみ）:
  - `~/.claude/agents/spec-planner-architect.md`
  - `~/.claude/agents/spec-planner-modeler.md`
  - `~/.claude/agents/spec-planner-requirements-analyst.md`
  - `~/.claude/agents/spec-planner-critic.md`
  - `~/.claude/agents/spec-planner-scribe.md`
  - `~/.claude/agents/japan-ehr-specialist.md`
  - `~/.claude/agents/japan-receipt-computer-specialist.md`
- 出力テンプレート: `~/.claude/skills/spec-planner-plan/templates/`
