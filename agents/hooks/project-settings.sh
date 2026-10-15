#!/usr/bin/env bash
# プロジェクトごとの Claude Code 設定 (.claude/settings.local.json) を private リポジトリで管理し、
# 各 checkout と worktree へ symlink で配る。
#   実体: $AGENT_PRIVATE_DIR/projects/<org>/<repo>/settings.local.json
#   配布先: <checkout>/.claude/settings.local.json (グローバル gitignore 済み)
#
# usage:
#   project-settings.sh link  <dir>...  実体があれば symlink を張る。実ファイルに化けていれば実体へ合流させて張り直す
#   project-settings.sh adopt <dir>...  link に加え、管理外の実ファイルを実体として取り込む
#   project-settings.sh all             実体のあるプロジェクトの本体 checkout と全 worktree に link する
#   (引数なし)                           Claude Code の hook として stdin の JSON の cwd に link する
#
# <org>/<repo> はメイン worktree の ~/src/github.com からの相対パスで決める。remote URL で決めないのは、
# org 指示 (~/src/github.com/<org>/CLAUDE.md) と同じく置き場所で効く範囲を揃えるため。
# hook と git-wt から呼ばれるので、失敗しても呼び出し元を止めないよう常に 0 で終える。

set -uo pipefail

PRIVATE_DIR="${AGENT_PRIVATE_DIR:-$HOME/src/github.com/wakwak3125/agent-private}"
SRC_ROOT="$HOME/src/github.com"

warn() { echo "project-settings: $*" >&2; }

# 「常に許可」で足された規則を落とさないよう、permissions の配列は和集合にする。
# それ以外のキーは checkout 側を新しい値とみなして優先する
merge_json() {
  jq -s '
    def uniq_keep_order: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
    .[0] as $a | .[1] as $b
    | ($a * $b)
    | reduce ("allow", "deny", "ask") as $k (.;
        if ($a.permissions[$k] == null and $b.permissions[$k] == null) then .
        else .permissions[$k] = ((($a.permissions[$k] // []) + ($b.permissions[$k] // [])) | uniq_keep_order) end)
  ' "$1" "$2"
}

# checkout のトップと、実体の置き場所を決める。対象外なら 1 を返す
resolve() {
  local dir="$1" common main key
  TOP="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ "$(basename "$common")" == ".git" ]] || return 1
  main="$(dirname "$common")"
  [[ "$main" == "$SRC_ROOT"/* ]] || return 1
  key="${main#"$SRC_ROOT"/}"
  STORE="$PRIVATE_DIR/projects/$key/settings.local.json"
  TARGET="$TOP/.claude/settings.local.json"
}

write_atomic() {
  local dest="$1" tmp
  tmp="$(mktemp "${dest}.XXXXXX")" || return 1
  if cat > "$tmp"; then
    mv "$tmp" "$dest"
  else
    rm -f "$tmp"
    return 1
  fi
}

link_one() {
  local dir="$1" adopt="$2" merged
  resolve "$dir" || return 0

  if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$STORE" ]]; then
    return 0
  fi

  if [[ ! -f "$STORE" ]]; then
    [[ "$adopt" == 1 && -f "$TARGET" && ! -L "$TARGET" ]] || return 0
    mkdir -p "$(dirname "$STORE")"
    cp "$TARGET" "$STORE"
    echo "project-settings: adopted $TARGET" >&2
  elif [[ -f "$TARGET" && ! -L "$TARGET" ]]; then
    # Claude Code が置き換え方式で書き込むと symlink が実ファイルに化けるので、ここで実体へ戻す
    if ! merged="$(merge_json "$STORE" "$TARGET")"; then
      warn "merge failed, leaving $TARGET as is"
      return 0
    fi
    printf '%s\n' "$merged" | write_atomic "$STORE" || return 0
    echo "project-settings: merged $TARGET into $STORE" >&2
  fi

  mkdir -p "$(dirname "$TARGET")"
  ln -sfn "$STORE" "$TARGET"
}

link_all() {
  local store key main wt
  [[ -d "$PRIVATE_DIR/projects" ]] || return 0
  while IFS= read -r store; do
    key="${store#"$PRIVATE_DIR/projects/"}"
    key="${key%/settings.local.json}"
    main="$SRC_ROOT/$key"
    [[ -d "$main/.git" ]] || continue
    while IFS= read -r wt; do
      link_one "$wt" 0
    done < <(git -C "$main" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  done < <(find "$PRIVATE_DIR/projects" -name settings.local.json -type f 2>/dev/null)
}

command -v jq >/dev/null 2>&1 || { warn "jq not found"; exit 0; }

case "${1:-}" in
  link | adopt)
    adopt=0
    [[ "$1" == adopt ]] && adopt=1
    shift
    for d in "$@"; do link_one "$d" "$adopt"; done
    ;;
  all)
    link_all
    ;;
  "")
    cwd="$(jq -r '.cwd // empty' 2>/dev/null)"
    [[ -n "$cwd" ]] && link_one "$cwd" 0
    ;;
  *)
    echo "usage: project-settings.sh <link|adopt> <dir>... | all" >&2
    ;;
esac
exit 0
