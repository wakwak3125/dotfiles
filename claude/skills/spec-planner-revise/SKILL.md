---
name: spec-planner-revise
description: spec-planner-plan で作成済みの設計成果物（design.md / data-model.md / requirements-mapping.md / usecases.md / open-issues.md / minutes.md / revision-history.md / critic-findings.md / task-state.md）を、ユーザーからの修正指示に基づいて改訂する。単発 subagent（architect / modeler / analyst / critic / scribe）を逐次呼び出し、blocker ゼロまで needs-revise ループを回す。改訂議事は `revision-history.md` に集約し、`minutes.md` には一切触らない。設計変更・仕様修正・未決事項の解決を議論込みで進めたいときに使う。
argument-hint: <修正指示の本文。先頭に対象スラグを `slug: <name>` 形式で指定可（省略時は自動検出）>
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, TaskCreate, TaskList, TaskUpdate, TaskGet
---

# spec-planner-revise: 既存設計を単発 subagent の逐次フローで改訂するスキル

あなたはこのスキルのファシリテーター（**オーケストレーター**）として動く。
spec-planner-plan で生成された既存成果物と、ユーザーからの修正指示を入力に、
**単発 `Agent` 呼び出し**を逐次発火し、critic の blocker 指摘が尽きるまで needs-revise ループを回して既存成果物を更新する。

**Agent-Team は使わない**。`TeamCreate` / `SendMessage` / `TeamDelete` は呼ばない。設計思想と呼び出し契約は `spec-planner-plan` と共通で、本スキルは**既存成果物の局所改訂**に最適化した逐次フローを提供する。

## このスキルが Opus 4.7 で動く前提

Opus 4.7 の挙動（subagent を控えめに spawn / tool より推論優先 / effort 厳格 / 字義通り解釈）に整合させた設計。設計思想は `spec-planner-plan` と完全に同一。以下が改訂モードに固有の重要点:

- **改訂は局所的・破壊禁止**: 既存判断を尊重し差分で動かす。指示の字義通りに、指示されていない箇所は触らない。Opus 4.7 は推測で広げない設計なのでこれと相性が良い
- **思考深度は steer**: 影響範囲の広い変更（design.md の改訂・最終 critic）は「Think carefully step-by-step. 既存判断との衝突を必ず確認」、定型作業（analyst の影響範囲特定・modeler のテーブル追記・scribe の整合修正）は「Respond directly」を入れる
- **コンテキスト前出し**: 修正指示・対象セクション・既存判断の要約・open-issues 一覧・受け入れ基準を 1 ターンで揃える。subagent に「過去の議論を読んで判断して」と委ねない（既存記述が一次情報）
- **ナレーション抑制**: メインは各ステップ後に `task-state.md` 更新と 1 行報告だけ。Opus 4.7 が自発的に出す進捗で十分

## 入力

`$ARGUMENTS` には以下が含まれる:
- **修正指示**（必須）: 何をどう直したいか。新要件追加、設計変更、open-issues 解消、モデル再検討、命名変更など
- **対象スラグ**（任意、推奨）: `slug: <name>` の形式で先頭に指定。省略時はフェーズ 0-1 で自動検出する

例:
- `slug: order-cancel 返金フローを外部決済プロバイダ切替に対応させる。冪等性要件を追加。`
- `open-issues の #3 と #5 を解決してほしい。必要ならデータモデルを修正してよい。`
- `ユースケース "在庫戻し" の並行実行に関する制約が曖昧。再検討して design.md を更新。`

---

## フェーズ 0: 事前チェックと準備

### 0-1. 対象ディレクトリの特定

`./spec-planner-output/` を確認し、対象スラグを決める:

1. `$ARGUMENTS` 冒頭に `slug: <name>` があれば最優先で採用
2. 無ければ `./spec-planner-output/` 配下のディレクトリを列挙:
   - 0 件: 「spec-planner-output が見つからない、または空」と伝えて中断。先に `spec-planner-plan` を実行してもらう
   - 1 件: 自動採用して使用スラグを 1 行通知
   - 2 件以上: 各スラグの `design.md` 冒頭 3 行と最終更新日時を一覧で提示し、ユーザーに指定を求めて中断。推測しない

採用した作業ディレクトリの絶対パスを `<WORKDIR>` として以降で使う。

### 0-2. 成果物の存在確認と欠損補完

`<WORKDIR>` 配下に以下が揃っているか確認する:

- `design.md` / `data-model.md` / `requirements-mapping.md` / `usecases.md` / `open-issues.md` / `minutes.md` / `revision-history.md`
- `critic-findings.md` / `task-state.md`（新運用で追加。旧 spec-planner-plan で生成された `<WORKDIR>` では欠落している可能性あり）

欠落があればユーザーに報告し「テンプレートから不足ファイルを補ってよいか」を確認する。承諾を得てから `~/.claude/skills/spec-planner-plan/templates/` から該当ファイルだけコピーする。無断で補わない。

### 0-3. 現状スナップショットの把握

メイン（あなた）は `<WORKDIR>` を通読せず、以下の最小情報だけ Read で拾う（全文 Read 禁止）:

- `design.md` 冒頭 20 行（目的とスコープ）
- `data-model.md` の主要テーブル一覧（見出しのみ抜粋）
- `open-issues.md` 全文（件数が多ければ重要度高のみ）
- `revision-history.md` 末尾の最新 Revision セクション 1 つ
- `task-state.md` 全文

この情報から「修正指示が影響を及ぼすファイルとセクション」を識別し、`task-state.md` の `Current Phase` を `revise-R{N}: 影響範囲特定中` に更新する（`{N}` は既存の Revision 番号 + 1）。

### 0-4. subagent 編成

既定は spec-planner-plan と同一の 5 役。subagent 定義は `~/.claude/agents/spec-planner-*.md` を流用する:

| 役 | subagent_type | 担当ファイル / 役割 |
|---|---|---|
| analyst | `spec-planner-requirements-analyst` | `requirements-mapping.md`（要求分解・影響範囲特定） |
| architect | `spec-planner-architect` | `design.md` / `open-issues.md`（設計改訂） |
| modeler | `spec-planner-modeler` | `data-model.md` / `usecases.md`（モデル改訂） |
| critic | `spec-planner-critic` | `critic-findings.md`（回帰レビュー重視） |
| scribe | `spec-planner-scribe` | 最終統合時のみ。`revision-history.md` 追記・整合・改訂箇所中心の削減 |

**ドメイン別オプション専門家**（追加条件は spec-planner-plan と同じ）: ehr / receipt。加えて、既存 `minutes.md` に `ehr` / `receipt` 発言の痕跡があれば既存判断との整合性のため今回も参加させる。

`$ARGUMENTS` にチーム構成指定があれば反映する。

---

## フェーズ 1: 単発 subagent の呼び出し契約

spec-planner-plan の「フェーズ 1」と**完全に同一**（10 件必須項目・思考深度 cue・受け入れ基準・全文 Read 禁止・戻り値 200 tokens 以内・critic は `critic-findings.md` 追記のみ・`model` 振り分けルールも共通）。本スキルでの `model` 割当は:

- **`"opus"`**: architect（ステップ 2 / 5）、最終 critic（ステップ 4 / 5）
- **`"sonnet"`**: analyst（ステップ 1 / 5）、modeler（ステップ 2 / 5）、軽量 critic（ステップ 3）、scribe（ステップ 6）、ehr / receipt（ステップ 4.5）

改訂モードでは `spec-planner-plan` の 10 項目に**加えて**、以下を必ず prompt に含める:

### 改訂モード専用の追加項目（prompt に必ず含める）

1. **モード明示**: 「これは新規設計ではなく**既存設計の改訂**。既存の判断と根拠を尊重し、変更する場合は `revision-history.md` に理由を残す。既存判断と整合する範囲で最小の差分を入れる」
2. **変更マーカー禁止**: 元ファイルに `v2` / `rev2` / `（改訂）` 等のマーカーを残さない。設計ドキュメントは常に「最新の確定版」として書く。履歴は `revision-history.md` のみに集約
3. **minutes.md 不可侵**: `minutes.md` は初回設計時の議事録。本スキルでは Read 不要（Write/Edit 禁止）
4. **改訂履歴の書き方**: `revision-history.md` の末尾に `## Revision R{N} (<YYYY-MM-DD>)` 見出しで追記。論点→結論の形式。逐語議論は書かない
5. **スコープ逸脱の扱い**: 修正指示と無関係な改善はその場で適用せず `open-issues.md` に提案として積む。**「ついでに」改善は禁止**（Opus 4.7 は字義通り従うのでこれは守られやすいが、明文化する）
6. **改訂モード受け入れ基準**: 改訂対象セクション以外を Edit していない / 既存の見出し構造を維持している / 採用した変更は `revision-history.md` の今回 Revision に反映済み
7. **critic 専用**: 「特に**回帰観点**を重視する。Think carefully step-by-step。この変更で壊れる既存要求はないか、`open-issues.md` との矛盾はないか、過去の `revision-history.md` で記録された判断と衝突しないかを明示的に洗う。Grep で要求 ID と既存 design 記述の整合を検証」

### critic 書き込み先

`critic-findings.md` の新規セクション `## Round {revise-R{N}-preliminary} (revise-R{N}, preliminary)` / `## Round {revise-R{N}-final} (revise-R{N}, final)` として追記する。既存の plan 時のラウンド行は消さない。

---

## フェーズ 2: 改訂逐次フロー（needs-revise ループ込み）

plan 側のフルフローを改訂用に短縮する。ステップ数と needs-revise ゲートの仕組みは共通。

### ステップ 1: analyst（単発・Sonnet・直接的）

- 目的: 修正指示を要求分解し、影響範囲（どのファイルのどのセクション）を特定。`requirements-mapping.md` に新規/変更要求の対応行を追記
- prompt 固有事項: 修正指示本文 + 0-3 で拾った冒頭抜粋 + `open-issues.md` 全文 + 思考深度 cue「Respond directly」
- 受け入れ基準: 影響を受けるファイルとセクションを 1 件以上特定。新規/変更要求が `requirements-mapping.md` に行追加されている
- 戻り値後: `task-state.md` の `Next Action` に「改訂対象ファイル: design.md §X / data-model.md §Y」等を記録

### ステップ 2: 該当ファイル改訂（単発・必要なものだけ）

影響範囲に応じて、以下のうち**必要な subagent だけ**単発呼び出しする（逐次のみ）:

- `design.md` / `open-issues.md` の改訂 → architect（Opus・「Think carefully step-by-step」）
- `data-model.md` / `usecases.md` の改訂 → modeler（Sonnet・「Respond directly」）
- 両方必要なら architect → modeler の順で逐次呼び出し（architect の更新が modeler の前提になりがちなため）

prompt 固有事項: 「対象セクションだけを Edit。章構成の大幅再編は不可。変更マーカー禁止。変更箇所の概要を戻り値 summary に 1 行で記載。指示にない箇所は触らない」
受け入れ基準: 改訂対象セクション以外を Edit していない / `revision-history.md` に変更概要が追記されている

### ステップ 3: 軽量 critic（単発・Sonnet・回帰熟考）

- 目的: 改訂箇所への回帰レビュー。blocker は「既存要求を壊す変更」「open-issues との矛盾」「過去 Revision との衝突」を最優先で検出
- prompt 固有事項: 思考深度 cue「Think carefully — 回帰観点を最優先で深掘り」
- 書き込み: `critic-findings.md` の `## Round (revise-R{N}, preliminary)` セクション
- 受け入れ基準: 最低 3 件の指摘 + severity タグ
- needs-revise ゲート:
  - `blocker == 0` → ステップ 4 へ
  - `blocker > 0` → 該当 subagent（architect / modeler / analyst）を再呼び出し。「`critic-findings.md` の `## Round (revise-R{N}, preliminary)` の blocker 行のみ対応し resolved に更新」を明示。再度このステップ 3 へ戻り、critic は `## Round (revise-R{N}, preliminary, retry N)` で再評価。最大 2 リトライ

### ステップ 4: 最終 critic（単発・Opus・厚めに熟考）

- 目的: 改訂完了後の最終確認。既存成果物全体と改訂差分の整合を厚めに見る
- prompt 固有事項: 「**Think carefully and step-by-step.** 改訂箇所を中心に、要求網羅・整合性・回帰リスク・非機能・過去 Revision との整合・既存 open-issues との矛盾の 6 軸を確認。Grep で cross-file の用語・ID・テーブル名整合性を検証。severity タグ必須」
- 書き込み: `critic-findings.md` の `## Round (revise-R{N}, final)` セクション
- 受け入れ基準: 6 軸それぞれに最低 1 件の検討記録（指摘なしでも「観点 X: 問題なし」を 1 行）

### ステップ 4.5: ドメイン専門家チェック（条件付き・単発・Sonnet）

- 条件: ehr / receipt を 0-4 で追加している場合のみ
- **fan-out 例外**: 両方を呼ぶ場合は逐次ではなく**並列**で発火してよい
- 書き込み: `## Round (revise-R{N}, domain-ehr)` / `(revise-R{N}, domain-receipt)`

### ステップ 5: needs-revise ループ

最終 critic の blocker をファイル担当者に配分し、blocker ゼロまで繰り返す。plan 側ステップ 7 と同一の仕組み:

- `design.md` / `open-issues.md` の blocker → architect を単発呼び出し
- `data-model.md` / `usecases.md` の blocker → modeler を単発呼び出し
- `requirements-mapping.md` の blocker → analyst を単発呼び出し
- 解消後は最終 critic を再度単発呼び出しして `## Round (revise-R{N}, final, retry M)` で確認
- 同じ論点で 2 ループ連続解消しないものは `deferred` → `open-issues.md` 送り
- 5 ループ超えそうならユーザーに中間報告（改訂は局所変更前提。長引く場合はスコープ膨張の可能性が高い）

### ステップ 6: scribe（単発・Sonnet・直接的）

blocker ゼロ確定後に 1 回だけ起動する。prompt 冒頭に思考深度 cue「Respond directly. 整合修正・削減・追記の機械的適用が中心」を入れたうえで、以下を順に指示:

1. **整合チェック**: 改訂箇所と既存記述の境目で、用語・ID・テーブル名・参照切れ・改訂マーカー混入（`v2` / `rev2` / `（改訂）` 等）が無いか Grep + 必要箇所 Read で確認。不整合は直接 Edit で直す
2. **30% 削減パス（改訂箇所中心）**: 今回改訂した箇所を中心に `design.md` / `usecases.md` / `requirements-mapping.md` の情報密度を上げて最低 30% 削減。明らかに重複する既存箇所の削減は可、ただしスコープ外の大規模書換は `revision-history.md` に「見送り提案」として記録するのみ
3. **冒頭整備**: `design.md` 冒頭「目的とスコープ」が改訂結果で古くなっていれば最短表現に更新。大幅変更がなければ触らない
4. **critic-findings の major/minor 反映**: `critic-findings.md` の今回 Revision 分 major/minor のうち採用するものを反映し status を `resolved` に更新
5. **Revision セクション総括**: `revision-history.md` の `## Revision R{N} (<YYYY-MM-DD>)` 末尾に「改訂まとめ」を追記。構成: 改訂指示の要約 / 合意した主要変更（ファイル別） / 見送った提案と理由 / 新規 open-issues
6. **未決整理**: `open-issues.md` を重要度順にソートし、新規追加項目には「放置した場合の影響」を記載
7. **minutes.md は触らない**（明示的に禁止）

## フェーズ 3: 報告

scribe 完了後、ユーザーに以下を 1 メッセージで報告:

- 作業ディレクトリの絶対パス
- 今回の Revision 番号 `R{N}` と実行した needs-revise ループ回数
- 変更したファイルと、それぞれで更新されたセクション見出し
- 解消した open-issues 件数 / 新規 open-issues 件数
- 見送った提案（あれば）3 件以内
- 特に注目すべき判断・論点 3 件以内

---

## 運営上の厳守事項

- **戻り値最小化**: 各 subagent の戻り値は `wrote: / summary: / findings_count:` 形式で最大 200 tokens
- **ファイル全文 Read 禁止**: メインも subagent も、必要なセクションだけ offset/limit で Read。Grep は cross-file 整合の検証用途。全文通読が必要なのは scribe の整合チェック時のみ
- **Agent-Team を使わない**: `TeamCreate` / `SendMessage` / `TeamDelete` を呼ばない
- **状態はファイルに**: 進捗・blocker 残数・次アクションは `task-state.md` / `critic-findings.md` に書く
- **needs-revise は blocker ゼロで閉じる**: major/minor は scribe 最終統合で処理
- **既存記述を破壊しない**: 改訂は差分で行う。大規模書換は合意後、あるいは `revision-history.md` に見送り提案として記録
- **スコープクリープ防止**: 修正指示と無関係な改善はその場で適用せず `open-issues.md` に提案として積む
- **改訂マーカー禁止**: 元ファイルに `v2` / `rev2` / `（改訂）` を残さない
- **minutes.md 不可侵**: 本スキルでは Write/Edit 禁止
- **字義通り解釈の徹底**: prompt に「同様に」「適切に」「自動的に」「必要に応じて」を書かない。Opus 4.7 は曖昧語を補完しない。受け入れ基準を満たさない戻り値は再依頼する
- **メインのナレーション抑制**: ステップ間の "now I will..." 系の前置きを書かない。Opus 4.7 は agentic trace で自然に進捗を返す
- **$ARGUMENTS の修正指示が曖昧な場合**: 即座に止めて、何を・なぜ・どこまで変えたいのかを問う。推測で進めない

## 参照

- 初回設計スキル（呼び出し契約の詳細はこちら）: `~/.claude/skills/spec-planner-plan/SKILL.md`
- subagent 定義: `~/.claude/agents/spec-planner-*.md`
- テンプレート（欠損補完用）: `~/.claude/skills/spec-planner-plan/templates/`
