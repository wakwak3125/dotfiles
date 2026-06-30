# 新規モード逐次フロー

> `spec-planner` SKILL.md のフェーズ 1 から参照される、新規設計用の単発 subagent 逐次フロー。
> 共通の subagent 呼び出し契約は [subagent-contract.md](./subagent-contract.md) を参照。

各ステップ完了時にメインは `task-state.md` の `Current Phase` / `Next Action` / `Completed Steps` を 1 回 Edit し、ユーザーには 1 行報告だけ返す。

## ステップ 1: analyst（単発・Sonnet・直接的）

- 目的: `requirements.md`（ステークホルダー向け要求仕様）+ `requirements-mapping.md`（開発者向け要求→設計対応表）の初版。要求分解と未対応要求の洗い出し
- 入力: `meeting-decisions.md` の `## Ad-hoc Instructions` + `## Decisions Timeline` を要求源とする。`base:` 文書はここで読み込んで `requirements-mapping.md` の「既存資料からの引継ぎ」セクションに反映
- prompt 固有事項:
  - 「`requirements.md` は**ステークホルダー（顧客・PdM・ビジネスサイド）が業務言語で読む文書**として書く。技術用語・API 名・テーブル名・実装詳細は書かない。何を・なぜ・誰のために作るかを 8 セクション（背景 / 目的とゴール / 対象ユーザー / 提供価値 / スコープ / ビジネス受入条件 / 制約と前提 / 関連ドキュメント）で埋める」
  - 「`requirements-mapping.md` は従来通り**開発者向けの要求→設計対応表**として書く。`requirements.md` の AC-{N} と requirements-mapping の要求 ID を相互参照させる」
  - 「`base:` 文書から拾える情報は `requirements.md` に反映する。情報不足の項目は空欄のまま残さず『未確定（要 MTG）』と明記して `open-issues.md` に転記する」
- 思考深度 cue「Respond directly」
- 受け入れ基準: 各要求行に ID / 受入条件 / 担当ファイル予定が埋まっている。未対応要求は別表で列挙。`requirements.md` の 8 セクションが具体的内容で書かれている

## ステップ 2: architect（単発・Opus・熟考）

- 目的: `design.md` / `open-issues.md` 初版。モジュール境界・主要設計判断
- prompt 固有事項: `requirements-mapping.md` は Read 可（offset/limit）。`design.md` 本文を Write。思考深度 cue「Think carefully and step-by-step」
- 受け入れ基準: 主要設計判断 3 件以上が「採用 + 却下案 + 却下理由」の形で散文で書かれている。`open-issues.md` に 1 件以上の未決事項

## ステップ 3: 軽量 critic 1（単発・Sonnet・熟考）

- 目的: architect 成果物への 1 往復レビュー。**design.md / open-issues.md のみが対象**
- prompt 固有事項: 「軽量レビュー（1 往復・最大 15 件）。severity タグ必須。blocker は要求未充足・整合性崩壊級のみ。Think carefully — 沈黙は劣化」
- 書き込み: `critic-findings.md` の `## Round 1 (preliminary-architect)` セクション
- 受け入れ基準: 最低 3 件の指摘。各 severity タグ付き。findings_count を返す

**needs-revise ゲート**:
- `blocker == 0` → ステップ 4 へ
- `blocker > 0` → architect を再度単発呼び出し。prompt に「`critic-findings.md` の `## Round 1 (preliminary-architect)` の blocker 行のみ対応し、当該行を resolved に書き換える。major/minor は今回触らない。design.md の該当セクションを Edit」を明示。再度このステップ 3 へ戻り、critic は同じラウンドに `## Round 1 (preliminary-architect, retry N)` 見出しで再評価。blocker ゼロまで最大 2 回リトライ。それでも残る場合はユーザーに中間報告して継続可否を問う

## ステップ 4: modeler（単発・Sonnet・直接的）

- 目的: `data-model.md` / `usecases.md` 初版。ER 図・テーブル定義・ユースケースの入出力と状態遷移
- prompt 固有事項: `design.md` の該当節と `requirements-mapping.md` を offset/limit で Read 可。思考深度 cue「Respond directly。正規化と状態遷移の標準手順を適用する作業」
- 受け入れ基準: 全テーブルに PK / 主要 FK / 制約が記載。各ユースケースに入力・出力・状態遷移が記載

## ステップ 5: 軽量 critic 2（単発・Sonnet・熟考）

- 目的: modeler 成果物への 1 往復レビュー。**data-model.md / usecases.md のみが対象**
- prompt 固有事項: 思考深度 cue「Think carefully — 並行競合・整合性・参照整合の観点で深掘り」
- 書き込み: `critic-findings.md` の `## Round 2 (preliminary-modeler)` セクション
- needs-revise ゲート: ステップ 3 と同じ仕組み。blocker > 0 なら modeler を再呼び出し、最大 2 リトライ

## ステップ 6: 最終 critic（単発・Opus・厚めに熟考）

- 目的: 全成果物を横断した最終レビュー。blocker / major / minor を洗い出し
- prompt 固有事項: 「**Think carefully and step-by-step.** 厚めレビュー。全成果物を offset/limit で必要部分だけ Read。Grep で要求 ID と設計記述・テーブル名・カラム名の cross-file 整合性を検証。要求網羅・整合性・非機能・障害シナリオ・運用観点・回帰リスク・**ステークホルダー読解性**（`requirements.md` がステークホルダー読者にとって読めるか、技術用語混入がないか）の 7 軸を一通り。severity タグ必須」
- 書き込み: `critic-findings.md` の `## Round 3 (final)` セクション
- 受け入れ基準: 7 軸それぞれに最低 1 件の検討記録（指摘なしでも「観点 X: 問題なし」を 1 行）

## ステップ 6.5: ドメイン専門家チェック（条件付き・単発・Sonnet）

- 条件: ehr / receipt を 0-2 で追加している場合のみ
- 目的: 法令・規格・点数・算定観点での最終確認（1 往復）
- **fan-out 例外**: ehr と receipt の両方を呼ぶ場合は逐次ではなく**並列**で発火してよい（互いの成果物に依存しないため）
- 書き込み: 指摘は `critic-findings.md` に `## Round 3.5 (domain-ehr)` / `(domain-receipt)` セクションで追記。severity タグは同じ基準
- blocker が増えた場合は次の needs-revise ループ（ステップ 7）に合流

## ステップ 7: needs-revise ループ

最終 critic（+ ドメイン専門家）が出した blocker を、ファイル担当者に配分して解消する:

- `design.md` / `open-issues.md` の blocker → architect を単発呼び出し（対象セクションと `critic-findings.md` の該当行を prompt に明示、該当行のみ resolved に更新させる）
- `data-model.md` / `usecases.md` の blocker → modeler を単発呼び出し
- `requirements.md` / `requirements-mapping.md` の blocker → analyst を単発呼び出し
- 複数ファイルに跨る blocker は、ファイルごとに分けて該当担当者を順に呼ぶ

全 blocker の status を `resolved` にしたら、再度**最終 critic を単発呼び出し**して残存 blocker を確認（`## Round 3 (final, retry N)`）。blocker ゼロが確認できるまで繰り返す。

- `major` / `minor` は今ループでは触らない。scribe の最終統合（ステップ 8）でまとめて処理させる（体裁・冗長は minor、設計品質の軽微な改善は major として対応）
- 同じ論点で 2 ループ連続して blocker ゼロに至らない場合は、その指摘を `deferred` にして `open-issues.md` に移送（理由と影響を明記）し、当該ループを閉じる
- 8 ループを超えそうと判断した時点でユーザーに中間報告し、継続可否を確認

## ステップ 8: scribe（単発・Sonnet・直接的）

blocker ゼロ確定後に 1 回だけ起動する。prompt 冒頭に思考深度 cue「Respond directly. 整合修正・削減・追記の機械的適用が中心」を入れたうえで、以下を順に指示:

1. **整合チェック**: 全成果物を offset/limit で走査 + Grep で用語・ID・テーブル名・カラム名・参照の一致を検証。不整合は直接 Edit で直す
2. **過去比較表現クレンジング**: SKILL.md の「過去比較表現クレンジング手順」を実行（`requirements.md` を含む 6 ファイル対象）
3. **`requirements.md` の技術用語検査**: API 名・テーブル名・クラス名・関数名等の技術固有名詞を Grep で検出し、見つかれば業務言語に置換するか削除する
4. **30% 削減パス**: `design.md` / `usecases.md` / `requirements-mapping.md` の情報密度を上げて最低 30% 行数削減:
   - 同じ内容を別の言い方で書いている箇所を統合
   - 自明な説明・冗長な前置き・目次の水増しを削除
   - 箇条書きを散文に書き換え（本当に列挙可能な離散項目は残す）
   - 抽象語単独の記述は具体化するか削除
   - 両論併記は採用決定＋却下理由の形に書き換える
   - `data-model.md` はもともと簡潔志向。重複整理程度
   - `requirements.md` はステークホルダー向けで読みやすさ優先のため削減対象外
5. **冒頭整備**: `design.md` 冒頭「目的とスコープ」を、既にシステムを知る熟練エンジニア向けに最短化。背景説明は書かない
6. **critic-findings の major/minor 反映**: `critic-findings.md` の major/minor 指摘のうち採用するものを各ファイルに反映し、status を `resolved` に更新
7. **議事録作成**: `minutes.md` に「MTG 決定の反映状況」と「設計内部での needs-revise ループ結論」を分けて書く。MTG 決定の逐語は転記しない（`meeting-decisions.md` が一次情報源）
8. **未決整理**: `open-issues.md` を重要度順にソートし、全項目に「放置した場合の影響」を記載

scribe の戻り値も `wrote: ..., summary: ...` 形式で 200 tokens 以内。
