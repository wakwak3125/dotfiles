# codex レビュー併用 (フェーズ 6)

設計判断が重い変更で、Claude reviewer 2 体に独立エンジンの網羅パスを足すときの手順。併用するかどうかの判断条件は SKILL.md フェーズ 6 側にある。

## review と adversarial-review の使い分け (自動判断)

- **`review`** — 仕様・設計は妥当という前提で、**実装の欠陥**を網羅的に拾いたいとき。バグ・認可漏れ・例外処理漏れ・境界条件・テスト不足。
- **`adversarial-review`** — 採ったアプローチ・設計判断・トレードオフ・**前提そのものを疑いたい**とき。新規抽象の導入、層配置の選択、公開境界の変更、複数の妥当な解釈があった設計判断を含む変更。

迷ったら、設計判断を含むなら `adversarial-review`、実装欠陥の洗い出しが主目的なら `review`。

## 起動方法 (Skill から直接 companion を呼ぶ)

codex コマンドは `disable-model-invocation` のため Skill から slash command を自動起動できない。代わりに codex-plugin-cc の companion スクリプトを直接実行する。`--wait` で同期実行し、出力をレビュー統合に使う:

```bash
COMPANION=$(ls -dt ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | head -1)
if [ -n "$COMPANION" ]; then
  node "$COMPANION" review --wait          # または adversarial-review --wait
else
  echo "codex-plugin-cc 未導入 — codex レビューはスキップ"
fi
```

## 運用ルール

- companion が見つからない / codex CLI 未セットアップ (`/codex:setup` 未実行) の場合は codex レビューをスキップし、その旨を最終報告に 1 行残す (Claude reviewer 2 体は通常通り実施)
- レビュー対象・重点観点・出力形式はすべて companion の既定 (working tree の diff、なければデフォルトブランチとの merge-base 差分) に任せる。Skill から渡すのは比較ベースが既定と異なるときの `--base <ref>` だけ
- codex の指摘は PASS / NEEDS_REVISION 形式とは限らない。メインが重大度を判定して must / imo 相当に振り分ける (処理ルールは SKILL.md「レビュー結果の処理」)
