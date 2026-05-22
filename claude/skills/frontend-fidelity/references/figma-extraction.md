# Figma 抽出

Figma MCP を使い、適切な詳細レベルで仕様を抽出する手順。

## セットアップ

Figma Dev Mode MCP サーバはユーザーが現在選択中(または指定)のフレームに対して操作を公開する。先に MCP が接続されているか確認すること。auth エラーで失敗するなら、Figma 側で Dev Mode MCP を有効化するようユーザーに依頼。

## 抽出する内容と順序

### 1. フレームメタデータ

対象ノード (フレーム URL またはノード ID):

- 名前と親フレーム
- 寸法 (width、height) — オートレイアウトを使っているか確認
- オートレイアウト使用時は: 方向、間隔、padding、整列

### 2. Variables (デザイントークン)

フレームと子孫が参照する変数を取得する。これが token-map の真実の源。

変数ごとに記録:

- 名前 (Figma 名 — `color/text/primary` のようなスラッシュ区切りもあり)
- 解決済みの値
- 型 (color、dimension、number、string)
- マルチモード時はコレクション/モード (例: light/dark)

これを token-map 手順 (`token-map-inference.md`) に渡す。

### 3. 構造

子孫を辿って、意味のあるノードごとに記録:

- レイヤー名 (semantics のヒントになることが多い: `Button/Primary`、`Card/Header`)
- デザインから推測される要素ロール — 見出しスタイル → `h*`、ラベル付きクリッカブル → `button` か `a`
- オートレイアウトプロパティ → flex/grid にマップ
- 制約 → レスポンシブ挙動にマップ

DOM に現れない装飾ノード (グルーピング目的のラッパー) はスキップ。

### 4. プロパティごとのトークン

残したノードごとに、各視覚プロパティの*トークン参照* (生の値ではなく) を記録:

- Fills、strokes → color トークン
- Effects (shadow、blur) → shadow トークン
- 角丸 → radius トークン
- Spacing (padding、gap) → spacing トークン
- Text → typography トークン (font family、size、weight、line height、letter spacing)

トークン参照でなく生の値だったらフラグを立てる。トークン不足 (ユーザーに報告)、または実装に存在すべきでない値のどちらか。

### 5. States と variants

Figma の component variants が state を表す。列挙する:

- component set (全 variant を持つ親) を見つける
- 各 variant のプロパティ組合せを列挙 (例: `state=hover, size=md`)
- variant ごとに 3〜4 を繰り返し、default との差分に注目

Figma の variant 名は妥当な範囲で story 名にマップする。

### 6. A11y のヒント

Figma は semantic 情報を確実には持たないが、以下のように推測できる:

- ラベル付き interactive shape → button または link
- アイコンに対する見えるラベル → `aria-label` または視覚的に隠しテキスト
- 見出しスタイルのテキスト → 適切なレベルの heading 要素
- 入力ふうの形 → label と control の関連付け

推測した a11y 義務は明示的に記録し、実装まで生き残らせる。

### 7. 検証用フレーム画像

予定するビューポート幅で各 variant の描画画像を要求。フェーズ 7 視覚比較のベースラインとして保存。

## やってはいけないこと

- Figma MCP に「コード」を要求しない — 自動生成コードはスタート地点であってゴールではない。仕様を抽出し、コードはプロジェクト慣習に従って自分で書く。
- 実装用に生のピクセル値を抽出しない。実装はトークン名を使い、生の値はトークン定義ファイル内のみ。
- 過剰抽出しない。DOM に現れない純粋な視覚ラッパーはスキップ。

## 出力形式

実装フェーズが消費できる構造化サマリを出力:

```
Frame: <name>
  Element: <semantic> (<node-name>)
    Tokens:
      color.fill: color.surface.primary
      spacing.padding-x: spacing.4
      ...
    States: default, hover, disabled
    A11y: role=button、label は内側テキストから推測
  ...
```

これがフェーズ 5 の契約となり、フェーズ 7 の検証仕様にもなる。
