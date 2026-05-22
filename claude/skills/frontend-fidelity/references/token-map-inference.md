# token-map 推論

Figma 変数とコード側トークンを自動的に突合し、実装が正しいトークン名を使えるようにする。手動 config なしで動くのが目標。

## 実行するタイミング

- プロジェクトで初めて Skill が走るとき
- 前回マップ構築以降、コード側トークン定義が変更されているとき (`/tmp/token-map.json` の mtime と比較)
- 対象フレームの Figma 変数に既存マップに無い名前が含まれるとき

## パース対象

### コード側

以下の順でトークン定義ファイルを探す:

1. `tokens.{ts,js,json}`、`design-tokens.{ts,js,json}` — 明示的なトークンファイル
2. `theme.{ts,js}`、`themes/*.{ts,js}` — styled-components / Emotion / Chakra 系で一般的
3. `tailwind.config.{js,ts,mjs,cjs}` — Tailwind theme; `theme` と `theme.extend` から抽出
4. `:root { --... }` ブロックを持つ CSS / SCSS — CSS カスタムプロパティ
5. Tailwind v4 の `@theme` ブロックや SCSS 変数 (`$variable`)

最初に実質的なトークン集合が得られたソースで停止。複数が共存する場合はすべてパースして union を取り、コンフリクト (同名・異値) を記録。

### フラットテーブルに正規化

`{ name, value, type, source }` レコードを生成:

```
{
  "name": "color.text.primary",
  "value": "#0F172A",
  "type": "color",
  "source": "src/theme.ts"
}
```

名前を正規化: `_`、`-`、`/`、`.`、camelCase 境界をすべて 1 つの区切り文字 (`.`) に統一。`colorTextPrimary`、`color-text-primary`、`color/text/primary` をマッチング目的で `color.text.primary` に揃える。元の名前は `canonicalName` として保持しコード生成に使う。

### Figma 側

Figma MCP で対象フレームが参照する全 variables を取得:

```
{
  "figmaName": "Color/Text/Primary",
  "value": "#0F172A",
  "type": "color",
  "mode": "light"
}
```

同じ正規化を適用。

## 突合アルゴリズム

各 Figma 変数について:

1. **値完全一致** — 同じ値 (同じ型) のコードトークンを検索。ちょうど 1 つならマップ確定。
2. **名前 + 値マッチ** — 値が複数のコードトークンに一致する場合、正規化名が Figma 名に最も近いものを採用 (Levenshtein または segment の重なり率)。
3. **名前のみマッチ (フォールバック)** — 値が一致しない (例: Figma は HSL、コードは HEX) 場合、正規化名でマッチ。
4. **未マッチ** — `unmatched` として Figma 値と名前を保持。

出力:

```json
{
  "matched": [
    { "figma": "Color/Text/Primary", "code": "color.text.primary", "value": "#0F172A" },
    ...
  ],
  "unmatched": [
    { "figma": "Color/Accent/Magenta", "value": "#FF0080", "type": "color" }
  ]
}
```

`/tmp/token-map.json` に永続化。

## 推論が失敗するとき

ユーザーに尋ねる閾値:

- **30% 超が未マッチ。** トークン体系がそもそもズレている可能性。ユーザーに対応 config (ユーザー管理の JSON) を要求し、それを正とする。
- **コード側ソース間のコンフリクト。** 同じ正規化名で異なる値が 2 ファイルにある。コンフリクトを報告しどちらが正かを確認。
- **片側だけマルチモード (light/dark)。** Figma にモードがあるがコードはフラット theme (またはその逆) なら、どのモードが対象かをユーザーに確認。

これらを取り繕わない。誤ったトークンは Skill の目的を破壊する。

## マップの使い方

フェーズ 5 の実装で:

- Figma 仕様が `Color/Text/Primary` を参照していたら、マップされたコードトークン (`color.text.primary`) を引き、コードベースが期待する形 (CSS 変数、theme アクセサ、Tailwind クラス — 既存の使用箇所を読んで合わせる) で使用。
- 未マッチの Figma 変数にマップされるプロパティについては、トークン名を捏造しない。プランでフラグを立て、ユーザーに確認する (デザインシステム側のトークン不足の可能性が高い)。
