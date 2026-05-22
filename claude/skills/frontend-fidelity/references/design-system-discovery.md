# デザインシステム棚卸し

既存の primitive を棚卸しし、再発明ではなく合成で実装するための手順。

## 探す場所

以下の順で探索し、デザインシステムが明確な場所が見つかったら停止:

1. `src/components/`、`src/ui/`、`src/design-system/`
2. `packages/*/src/components/`、`packages/*/ui/` (モノレポ慣習)
3. `app/components/`、`lib/components/` (Next.js 慣習)
4. Storybook 設定 (`*.storybook*`) の `stories` glob — canonical なコンポーネント配置を指す

公開デザインシステム (`@company/ui`、`@org/design-system`) を使っていればそれも検索対象に含める。

## 棚卸しの仕方

候補 primitive ごとに記録:

- **名前と import パス** (`Button` from `@/components/ui/button`)
- **Props 表面積** — props インターフェースを読む
- **Variants / sizes** — primitive 自身のパラメータ化方法
- **合成スロット** — `children` を受けるか、`leftIcon` のような slot プロパティか、特定形のみか
- **既存使用箇所** — 通常どう合成されているか import を grep して確認

明らかに内部用の primitive (`_internal`、`private` 配下、アンダースコア接頭) はスキップ。ただしプロジェクトのパターン上、外部利用されていれば対象。

## Figma 仕様とのマッチング

フェーズ 4 (figma-extraction) で抽出した要素ごとに:

1. semantic ロール (button 系、card 系、input 系) で候補 primitive を絞る
2. 必要な variants と states をサポートしているか確認
3. 必要な children / slot を受けるか確認
4. トークン使用を確認 — primitive がトークンシステムに既に紐付いていること。内部で raw value を使っているなら、それは回避ではなく報告すべき問題。

マッチ成立 = 「この Figma 要素の実装 = primitive X をこの props で合成」。フェーズ 5 が機械的に適用できるよう記録する。

## マッチする primitive がない場合

新規低レベル実装に入る前に:

- 複数の既存 primitive に分解できないか再確認
- 既存 primitive が*ほぼ*合っていて variant 追加で対応できないか確認(複製でなく拡張)
- 必要なのは新規 primitive ではなく*合成* (既存 primitive を組み合わせた中レベルコンポーネント) ではないか確認

新規 primitive を書くのは以下すべて満たすとき:

- 既存 primitive がユースケースをカバーしない
- 再利用される (1 回限りなら primitive 化の根拠にならない)
- ユーザーがデザインシステム追加であると示唆した、またはコードベースのパターン上 primitive がコンポーネントファイル内に住む慣習である

新規 primitive を書くときは、既存のものの構造 (ファイル配置、props 規約、トークン使用、story 形式) を必ず模倣する。一貫性のための非妥協ルール。

## 出力

実装前にユーザーが妥当性確認できる対応表を出力:

```
Figma 要素 → 実装プラン
- Button/Primary    → <Button variant="primary" />
- Card/Header       → <Card> with <Card.Header> スロット
- Avatar+Name 行    → <Avatar /> + <Text variant="body"> の合成、新規 primitive 不要
```

この対応表に穴がある (「X 用の primitive が見つからない」) 場合は、実装に入る前に `dev-task` のプラン段階で報告する。
