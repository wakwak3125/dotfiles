# Critic Findings

各 critic ステップでの指摘を追記する。blocker 解消まで needs-revise ループに使う。

severity の基準:
- `blocker`: 採用できない設計上の致命欠陥。要求未充足・整合性崩壊・データ損失・法令違反など。必ず該当 subagent に修正を依頼する
- `major`: 採用は可能だが設計品質を大きく損なう。時間が許せば修正する
- `minor`: 体裁・記述の冗長・用語ゆれなど。scribe の最終統合でまとめて処理可能

status の遷移:
- `open`: 未対応
- `resolved`: 該当 subagent が修正し、次回 critic で再確認して問題なしとされた
- `deferred`: 今回スコープ外と合意。`open-issues.md` に移送してから close

## Round {N} ({段階名: preliminary-architect / preliminary-modeler / final / revise-R{M}})

| # | severity | file | section | finding | assigned_to | status |
|---|---|---|---|---|---|---|
| 1 | blocker | design.md | §3 モジュール境界 | （指摘本文） | architect | open |

<!-- 以降、ラウンドごとに ## Round 見出しを追加して追記する。過去ラウンドの行は消さない。 -->
