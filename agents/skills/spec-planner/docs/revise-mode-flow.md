# 改訂モード逐次フロー

> `spec-planner` SKILL.md のフェーズ 1 から参照される、既存設計の改訂用の単発 subagent 逐次フロー。
> 共通の subagent 呼び出し契約は [subagent-contract.md](./subagent-contract.md) を参照。

Revision 番号は既存の `revision-history.md` 末尾 +1。各ステップ完了時にメインは `task-state.md` の `Current Phase` / `Next Action` を 1 回 Edit し、ユーザーには 1 行報告だけ返す。

## 改訂モード固有の追加 prompt 項目（subagent-contract.md の 10 件 + sync 共通 3 件に**加えて**毎回必ず含める）

1. **モード明示**: 「これは新規設計ではなく**既存設計の改訂**。既存の判断と根拠を尊重し、変更する場合は `revision-history.md` に理由を残す。既存判断と整合する範囲で最小の差分を入れる」
2. **変更マーカー禁止**: 元ファイルに `v2` / `rev2` / `（改訂）` 等のマーカーを残さない。設計ドキュメントは常に「最新の確定版」として書く。履歴は `revision-history.md` のみに集約
3. **minutes.md 不可侵**: `minutes.md` は初回設計時の議事録。改訂モードでは Read 不要（Write/Edit 禁止）
4. **改訂履歴の書き方**: `revision-history.md` の末尾に `## Revision R{N} (<YYYY-MM-DD>)` 見出しで追記。論点→結論の形式。逐語議論は書かない
5. **スコープ逸脱の扱い**: 修正指示と無関係な改善はその場で適用せず `open-issues.md` に提案として積む。**「ついでに」改善は禁止**
6. **改訂モード受け入れ基準**: 改訂対象セクション以外を Edit していない / 既存の見出し構造を維持している / 採用した変更は `revision-history.md` の今回 Revision に反映済み
7. **過去議論・比較禁止**: 「成果物本文に過去比較表現を一切残さない。旧仕様の痕跡（消えた章・古いカラム名・以前の決定への言及）は本文から完全に削除し、`revision-history.md` の `## Revision R{N}` セクションに移送する。本文は新規読者が前提知識なく読める『最新の確定版』として書く」
8. **critic 専用**: 「特に**回帰観点**を重視する。Think carefully step-by-step。この変更で壊れる既存要求はないか、`open-issues.md` との矛盾はないか、過去の `revision-history.md` で記録された判断と衝突しないかを明示的に洗う。Grep で要求 ID と既存 design 記述の整合を検証」

## critic 書き込み先

`critic-findings.md` の新規セクション `## Round (revise-R{N}, preliminary)` / `## Round (revise-R{N}, final)` として追記する。既存のラウンド行は消さない。

## ステップ 1: analyst（単発・Sonnet・直接的）

- 目的: 修正指示を要求分解し、影響範囲（どのファイルのどのセクション）を特定。`requirements-mapping.md` に新規/変更要求の対応行を追記。必要なら `requirements.md` も更新
- 入力: `meeting-decisions.md` の `## Ad-hoc Instructions` + 今回追加された `## Decisions Timeline` 行（前回 Revision 時点との差分）。前回までの議事は既に `revision-history.md` に集約されているので再取り込みしない
- 担当ファイル拡張: 影響範囲に `requirements.md` の更新が必要かを判定する。スコープ変更・対象ユーザー追加・ビジネス受入条件の修正・期日変更等が含まれる場合は `requirements.md` も改訂対象に含める。技術詳細だけの改訂なら `requirements.md` は触らない
- `requirements.md` の改訂時 prompt: 「**ステークホルダーが業務言語で読む文書**であることを再確認し、技術用語混入の有無を検査。MTG 決定によりスコープ / 提供価値 / 受入条件が変わった場合は該当セクションを Edit。`requirements-mapping.md` との要求 ID / AC-{N} の対応関係を維持」
- 影響範囲特定: 「今回の MTG 決定で覆された過去判断」を `revision-history.md` の過去 Revision とクロスチェックする。衝突があれば critic の回帰観点として最優先で見させる
- 思考深度 cue「Respond directly」
- 受け入れ基準: 影響を受けるファイルとセクションを 1 件以上特定。新規/変更要求が `requirements-mapping.md` に行追加されている
- 戻り値後: `task-state.md` の `Next Action` に「改訂対象ファイル: design.md §X / data-model.md §Y」等を記録

## ステップ 2: 該当ファイル改訂（単発・必要なものだけ）

影響範囲に応じて、以下のうち**必要な subagent だけ**単発呼び出しする（逐次のみ）:

- `design.md` / `open-issues.md` の改訂 → architect（Opus・「Think carefully step-by-step」）
- `data-model.md` / `usecases.md` の改訂 → modeler（Sonnet・「Respond directly」）
- `requirements.md` / `requirements-mapping.md` の改訂 → analyst を再呼び出し
- 両方必要なら architect → modeler の順で逐次呼び出し（architect の更新が modeler の前提になりがちなため）

prompt 固有事項: 「対象セクションだけを Edit。章構成の大幅再編は不可。変更マーカー禁止。変更箇所の概要を戻り値 summary に 1 行で記載。指示にない箇所は触らない」
受け入れ基準: 改訂対象セクション以外を Edit していない / `revision-history.md` に変更概要が追記されている

## ステップ 3: 軽量 critic（単発・Sonnet・回帰熟考）

- 目的: 改訂箇所への回帰レビュー。blocker は「既存要求を壊す変更」「open-issues との矛盾」「過去 Revision との衝突」を最優先で検出
- prompt 固有事項: 思考深度 cue「Think carefully — 回帰観点を最優先で深掘り」
- 書き込み: `critic-findings.md` の `## Round (revise-R{N}, preliminary)` セクション
- 受け入れ基準: 最低 3 件の指摘 + severity タグ
- needs-revise ゲート:
  - `blocker == 0` → ステップ 4 へ
  - `blocker > 0` → 該当 subagent（architect / modeler / analyst）を再呼び出し。「`critic-findings.md` の `## Round (revise-R{N}, preliminary)` の blocker 行のみ対応し resolved に更新」を明示。再度このステップ 3 へ戻り、critic は `## Round (revise-R{N}, preliminary, retry N)` で再評価。最大 2 リトライ

## ステップ 4: 最終 critic（単発・Opus・厚めに熟考）

- 目的: 改訂完了後の最終確認。既存成果物全体と改訂差分の整合を厚めに見る
- prompt 固有事項: 「**Think carefully and step-by-step.** 改訂箇所を中心に、要求網羅・整合性・回帰リスク・非機能・過去 Revision との整合・既存 open-issues との矛盾・**ステークホルダー読解性**（`requirements.md` の技術用語混入チェック）の 7 軸を確認。Grep で cross-file の用語・ID・テーブル名整合性を検証。severity タグ必須」
- 書き込み: `critic-findings.md` の `## Round (revise-R{N}, final)` セクション
- 受け入れ基準: 7 軸それぞれに最低 1 件の検討記録（指摘なしでも「観点 X: 問題なし」を 1 行）

## ステップ 4.5: ドメイン専門家チェック（条件付き・単発・Sonnet）

- 条件: ehr / receipt を追加している場合のみ
- **fan-out 例外**: 両方を呼ぶ場合は逐次ではなく**並列**で発火してよい
- 書き込み: `## Round (revise-R{N}, domain-ehr)` / `(revise-R{N}, domain-receipt)`

## ステップ 5: needs-revise ループ

最終 critic の blocker をファイル担当者に配分し、blocker ゼロまで繰り返す:

- `design.md` / `open-issues.md` の blocker → architect を単発呼び出し
- `data-model.md` / `usecases.md` の blocker → modeler を単発呼び出し
- `requirements.md` / `requirements-mapping.md` の blocker → analyst を単発呼び出し
- 解消後は最終 critic を再度単発呼び出しして `## Round (revise-R{N}, final, retry M)` で確認
- 同じ論点で 2 ループ連続解消しないものは `deferred` → `open-issues.md` 送り
- 5 ループ超えそうならユーザーに中間報告（改訂は局所変更前提。長引く場合はスコープ膨張の可能性が高い）

## ステップ 6: scribe（単発・Sonnet・直接的）

blocker ゼロ確定後に 1 回だけ起動する。prompt 冒頭に思考深度 cue「Respond directly. 整合修正・削減・追記の機械的適用が中心」を入れたうえで、以下を順に指示:

1. **整合チェック**: 改訂箇所と既存記述の境目で、用語・ID・テーブル名・参照切れ・改訂マーカー混入（`v2` / `rev2` / `（改訂）` 等）が無いか Grep + 必要箇所 Read で確認。不整合は直接 Edit で直す
2. **過去比較表現クレンジング**: SKILL.md の「過去比較表現クレンジング手順」を実行（`requirements.md` を含む 6 ファイル対象）。検出 → 除去 → `revision-history.md` の `## Revision R{N}` セクション末尾 `### 設計書から除去した過去比較記述` に移送
3. **`requirements.md` の技術用語検査**: 改訂されている場合のみ、API 名・テーブル名・クラス名・関数名等の技術固有名詞を Grep で検出し、見つかれば業務言語に置換するか削除する
4. **30% 削減パス（改訂箇所中心）**: 今回改訂した箇所を中心に `design.md` / `usecases.md` / `requirements-mapping.md` の情報密度を上げて最低 30% 削減。明らかに重複する既存箇所の削減は可、ただしスコープ外の大規模書換は `revision-history.md` に「見送り提案」として記録するのみ
5. **冒頭整備**: `design.md` 冒頭「目的とスコープ」が改訂結果で古くなっていれば最短表現に更新。大幅変更がなければ触らない
6. **critic-findings の major/minor 反映**: `critic-findings.md` の今回 Revision 分 major/minor のうち採用するものを反映し status を `resolved` に更新
7. **Revision セクション総括**: `revision-history.md` の `## Revision R{N} (<YYYY-MM-DD>)` 末尾に「改訂まとめ」を追記。構成: 改訂指示の要約 / 合意した主要変更（ファイル別） / 見送った提案と理由 / 新規 open-issues / 設計書から除去した過去比較記述 / 今回取り込んだ `meeting-decisions.md` の `## Sources` 行（`### MTG ソース` 見出しで）
8. **未決整理**: `open-issues.md` を重要度順にソートし、新規追加項目には「放置した場合の影響」を記載
9. **minutes.md は触らない**（明示的に禁止）
