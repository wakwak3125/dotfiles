# React TypeScript

`dev-task` で React TS コードを書く前に読むこと。

> Figma 起点の視覚再現タスクは `frontend-fidelity` Skill に委譲する。本ファイルはあらゆる React TS 変更に通用するロジック/構造のパターンを扱う。

## 型

- `any` を避ける。`unknown` + 絞り込みでほぼ対応可能。
- `as` キャストを避ける。値の型が不明なら、ソース側の型を直すか型ガードで絞り込む。
- コンポーネントの variants や reducer の action は discriminated union を優先:
  ```ts
  type ButtonProps =
    | { kind: 'primary'; label: string }
    | { kind: 'icon'; icon: ReactNode; ariaLabel: string };
  ```
- すべての型を export しない。内部の形は内部に留め、export される型はモジュールの契約として扱う。

## コンポーネント

- 関数コンポーネントのみ。export は名前付きを既定とし、ファイルの既存慣習に合わせる。
- 1 ファイル 1 コンポーネント。密結合で常に一緒に使われる場合のみ例外。
- props インターフェース名は `<Component>Props`。任意 props のデフォルトは型ではなく分割代入時に明示。

## Hooks

- トップレベルのみ。条件付き呼び出しやコールバック内呼び出しはしない。
- `useCallback` / `useMemo` は計測可能な理由(memo 化された子の依存安定、重い計算)がある場合のみ。先回りの memo 化は悪臭。
- `useEffect` の依存配列は exhaustive。lint を抑制するなら理由をコメントに残す。
- カスタムフックは `use` で始め、安定した形を返す(レンダー毎に異なるオブジェクトを返さない)。

## State

- 冗長な state より derived value を優先。props/state から計算できるなら計算する。
- 状態遷移が状態機械なら `useState` を多用するより `useReducer`。
- まずはローカルに。兄弟が必要になれば持ち上げ、本当に横断的な値のみ context へ。

## 非同期パターン

- プロジェクトのデータ取得スタック (React Query、SWR 等) を使う。新規導入しない。
- `useEffect` 内の fetch のレースは キャンセルフラグか `AbortController` で対処。
- エラーとローディングはファーストクラスの状態。後付けにしない。

## import と構造

- 既存の import 順とグルーピングに合わせる。プラグインで強制されていることが多いので逆らわない。
- コンポーネント、スタイル、テスト、ストーリーはプロジェクト慣習どおりに同居させる。
- パスエイリアス (`@/components/...`) も既存の使い方に従う。

## アンチパターン

- memo 化された受け手の props に無名関数をインラインで渡す(memo の意味がなくなる)。
- derived data に `useEffect` を使う(レンダー内で計算する)。
- props 由来の derived state を `useEffect` + `setState` で同期する(レンダー内計算か `useMemo`)。
- サニタイズなしの `dangerouslySetInnerHTML`。
- 並べ替え可能なリストで index を `key` に使う。

## テスト

- プロジェクトのフレームワーク (Vitest / Jest + React Testing Library) を使う。新規導入しない。
- 実装ではなく振る舞いをテスト。class 名ではなく role / label / text でクエリ。
- 1 テスト 1 アサーションパス。
