# 単発 subagent の呼び出し契約

> `spec-planner` SKILL.md のフェーズ 1 から参照される共通契約。すべての subagent 呼び出し（新規モード / 改訂モードの双方）でこの契約に従う。

すべての subagent 呼び出しは**単発 `Agent` tool**で行う。毎回必ず以下を守る。

## 呼び出し時のパラメータ

- `subagent_type`: 後述の subagent 一覧から選ぶ
- `description`: 3〜5 語の動作説明（例: "architect: design.md initial draft"）
- `prompt`: 下記「prompt に毎回含める項目」を全件充足すること。本質的に不要なコンテキストは渡さない
- 並列化は**しない**（このスキルは逐次が前提）。例外はドメイン専門家複数（ehr / receipt）の同時呼び出し。逐次が必要なのは前ステップ成果物が次の入力になるため
- `model`: 役割ごとに明示指定する（agent 定義側の `model: inherit` を上書き）。Opus 4.7 は effort を厳密に守るため、深い判断が要る役は必ず Opus、定型作業は Sonnet に倒す:
  - **`"opus"`**: architect（初期設計 / 改訂時の design.md 改訂）、最終 critic
  - **`"sonnet"`**: analyst、modeler、軽量 critic、scribe、ehr / receipt
  - どちらか迷ったら Sonnet を先に試す。当該ステップで blocker が多発する場合だけ Opus に上げる

## subagent 一覧

| 役 | subagent_type | 担当ファイル / 役割 |
|---|---|---|
| analyst | `spec-planner-requirements-analyst` | `requirements.md`（ステークホルダー向け要求仕様）/ `requirements-mapping.md`（要求分解・対応表） |
| architect | `spec-planner-architect` | `design.md` / `open-issues.md`（全体設計・モジュール境界） |
| modeler | `spec-planner-modeler` | `data-model.md` / `usecases.md`（テーブル・ER・ユースケース） |
| critic | `spec-planner-critic` | `critic-findings.md`（批判的レビュー。本文は書かず指摘行のみ追記） |
| scribe | `spec-planner-scribe` | 最終統合時のみ起動。全ファイルの整合・削減・冒頭整備・議事総括 |

**ドメイン別オプション専門家**（`$ARGUMENTS` 検出または明示指定で追加）:

| 役 | subagent_type | 追加条件 |
|---|---|---|
| ehr | `japan-ehr-specialist` | 「電子カルテ」「EHR」「診療録」「SS-MIX」「FHIR」「医療情報」「電子処方箋」「PHR」等を検出、または明示指定 |
| receipt | `japan-receipt-computer-specialist` | 「レセコン」「診療報酬」「点数算定」「レセプト」「医事」「算定要件」「施設基準」等を検出、または明示指定 |

医療ドメインでは法令・規格は ehr、点数・算定は receipt の委譲ルールで役割が分かれる。両方同時に呼ぶことが多い。最終 critic の後に 1 往復だけドメインチェックを挟む。

## prompt に毎回含める項目（10 件すべて必須・順序は守る）

1. **モード宣言**: 「単発実行。このセッション内で完結させる。作業後に ~200 tokens のサマリだけ返す」
2. **思考深度の cue**:
   - 深い判断が要る役（architect / 最終 critic / 軽量 critic）: 「**Think carefully and step-by-step.** 設計判断のひとつひとつが下流に波及する。代替案を 1 つ以上検討してから採用判断を書け」
   - 定型作業の役（analyst / modeler / scribe / ehr / receipt）: 「**Respond directly.** 既知の手順を適用するだけの作業。過剰な熟考はしない」
3. **作業ディレクトリ絶対パス**: `<WORKDIR>` を絶対パス化したもの
4. **今回の担当範囲**: 対象ファイルと対象セクション。「全体書き換え」「他のファイルも見て調整」は禁止
5. **読んでよいファイル**: 当該 subagent の担当ファイル + `task-state.md` + 直前ステップの成果物（明示列挙）+ `meeting-decisions.md`（sync 固有の恒久追加）。**全文 Read は禁止。必要なセクションのみ offset/limit で Read**。Grep は cross-file ID/用語整合性の検証用途のみ。`.cache/` 配下は読ませない（メインが正規化済みのため）
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
    - **読み手はこのシステムを既に知る熟練エンジニア**（`requirements.md` は例外でステークホルダー視点で書く）。背景説明・用語定義・一般論は書かない
    - **箇条書きは本当に列挙可能な離散項目のみ**。設計判断の理由・経緯・トレードオフは**散文**で書く
    - **採用した決定と、却下した代替案を却下理由とともに書く**。両論併記やトレードオフの羅列は禁止
    - **抽象語単独禁止**。「スケーラブル」「堅牢」「高性能」等は、具体的な数値・メカニズム・具体例を添えなければ書かない
    - 初稿完成後に scribe が「30% 削減・情報密度向上」パスを行う

## sync 固有の追加項目（10 件必須項目に加えて毎回含める）

1. **MTG 議事優先**: 「`<WORKDIR>/meeting-decisions.md` を `## Decisions Timeline` 末尾から逆順で必ず Read する。`base:` 文書と `meeting-decisions.md` が矛盾する場合は **MTG 決定を優先**する。base は土台、MTG は最新の合意」
2. **議事の根拠付与**: 「設計判断に MTG 決定が影響する場合、`design.md` / `data-model.md` の該当箇所に `MTG-<YYYY-MM-DD>` の根拠タグを残す（散文の中に 1 箇所付ければよい。乱発しない）」
3. **設計書本文は『最新の確定版』として書く**:
   - `requirements.md` / `design.md` / `data-model.md` / `requirements-mapping.md` / `usecases.md` / `open-issues.md` の本文に、**過去 Revision との比較・変更経緯・以前の判断への言及を一切書かない**
   - 禁止表現の具体例: 「以前は」「もともとは」「当初は」「変更前」「変更後」「Revision R{N} では」「過去の判断では」「旧仕様」「新仕様」「旧モデル」「新モデル」「以前のバージョンでは」「v1 では」「rev1 では」
   - 採用した判断は**現在形で**書く。却下した代替案は「採用案 + 却下案 + 却下理由」の既存形式に従う（これは過去比較ではなく、設計検討の記録）
   - 改訂時に消えた旧仕様の記録は `revision-history.md` のみに残す。設計書本文からは痕跡を完全に消す
   - **理由**: 仕様はいつ誰がどのタイミングで読み始めても、過去の議論や前提知識なしに最新の確定版として理解できる必要がある

## critic 専用の追加契約

- 議論文・根拠文をメインに返さない。`critic-findings.md` に表形式で追記する
- 各指摘に `severity = blocker | major | minor` を必ず付ける
- `blocker` は「要求未充足・整合性崩壊・データ損失・法令違反など、採用不可級の欠陥」に限定する
- 戻り値の `findings_count` は当該ラウンドで追加した件数。以前のラウンド分は含めない
- 「沈黙＝合格」を許さない。観点が思いつかない場合でも障害シナリオ・並行性・運用・回帰の各軸から最低 1 件は出す（軽量 critic は最大 15 件）

## Opus 4.7 整合の前提

このスキルが Opus 4.7 で安定動作するための前提:

- **単発 subagent 逐次フローは Opus 4.7 と相性が良い**: 前ステップの成果物が次ステップの入力になるドメインで並列 fan-out は不要。subagent 1 体ごとに独立成果物を 1 ファイル吐かせることで、メインのコンテキストと判断負荷を最小化する
- **指示は字義通り**: 「同様に」「適切に」「自動的に」「必要に応じて」等の曖昧語を prompt に書かない。何を / どのファイルの / どのセクションに / どんな形式で書くかを毎回明示する。Opus 4.7 は推測で補完しない
- **思考深度は prompt で steer する**: 深い設計判断（architect / 最終 critic）は **「Think carefully step-by-step」** を必ず入れる。定型作業（analyst / modeler / scribe）は **「Respond directly. 過剰な熟考は不要」** を入れる
- **tool 呼び出しは推論より控えめが既定**: 各 subagent には「読むべきセクションは offset/limit で必要箇所のみ。Grep は cross-file 整合性の確認用途に限る」と毎回書く
- **進捗ナレーションは control する**: メインは各ステップ完了後に `task-state.md` 更新 + 1 行報告だけに留め、"now I will..." 系のナレーションは出さない
- **コンテキスト前出し**: 各 subagent には 1 ターンで完結する全情報（タスク意図 / 制約 / 受け入れ基準 / 対象ファイルとセクション / 許可された Read 範囲 / 成果物フォーマット）を初回 prompt に揃える
