#!/usr/bin/env bash
# コードレビュー用の herdr tab を一発で組み立てる。
#   左 pane: hunk (PR があれば gh pr diff | hunk patch、なければベースブランチとの diff)
#   右 pane: Claude Code (hunk セッションへインラインコメントを書くレビュアー)
# workspace は 案A 規約 (workspace = repo) に従い、同じ repo の workspace が
# あればそこへ review tab を追加し、なければ repo 名で workspace を作る。
# herdr 内 (HERDR_ENV=1) からの実行が前提。他の skill / agent からも直接呼べる。
#
# usage: open-review-space.sh [-C <repo-dir>] [PR番号]
#   PR番号省略時: カレントブランチの PR を解決し、なければ diff モードになる

set -euo pipefail

# tab 作成後に失敗した場合は中途半端な tab を残さず、再実行を安全にする。
# die() 経由に限らず set -e の暗黙 exit でも走るよう EXIT trap で行う
cleanup_tab_id=""
trap '[[ -n "$cleanup_tab_id" ]] && herdr tab close "$cleanup_tab_id" >/dev/null 2>&1 || true' EXIT

die() {
  echo "error: $*" >&2
  exit 1
}

repo_dir=""
while getopts "C:h" opt; do
  case "$opt" in
    C) repo_dir="$OPTARG" ;;
    h)
      # 先頭ヘッダブロックだけを usage として出す (本文中のコメントは含めない)
      sed -n '2,/^$/{s/^# \{0,1\}//p;}' "$0"
      exit 0
      ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))
pr="${1:-}"

[[ "${HERDR_ENV:-}" == "1" ]] || die "herdr の外では実行できない (HERDR_ENV != 1)"
for cmd in herdr jq gh hunk git; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd が見つからない"
done

[[ -n "$repo_dir" ]] && cd "$repo_dir"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git リポジトリ内で実行すること"
cd "$repo"

if [[ -z "$pr" ]]; then
  # PR がなければエラーにせず diff モード (PR 作成前のセルフレビュー) に落とす。
  # merged/closed も返ってくるので open な PR だけを対象にする
  pr="$(gh pr view --json number,state --jq 'select(.state == "OPEN") | .number' 2>/dev/null || true)"
else
  [[ "$pr" =~ ^[0-9]+$ ]] || die "PR 番号が不正: $pr"
  # 存在しない番号だと後段の gh pr diff の失敗が「hunk の起動を確認できない」に
  # 化けて原因を追いにくいため、ここで検証して具体的なエラーで止める
  gh pr view "$pr" --json number >/dev/null 2>&1 || die "PR #$pr を取得できない (番号と gh auth を確認すること)"
fi

repo_name="$(basename "$repo")"
branch="$(git branch --show-current 2>/dev/null)"
branch_short="${branch##*/}"
[[ -n "$branch_short" ]] || branch_short="detached"

merge_base=""
if [[ -n "$pr" ]]; then
  mode="pr"
  tab_label="review:#${pr}"
  target_desc="PR #${pr}"
  # stdin パイプだと hunk がキーボードを読めなくなる (stdin が TTY でなくなる) ため、
  # patch は一時ファイルに落としてから開く
  patch_file="${TMPDIR:-/tmp}/review-space-$(printf '%s' "$repo_name" | tr -c 'a-zA-Z0-9_-' '-')-pr${pr}.patch"
  hunk_cmd="gh pr diff $pr > \"$patch_file\" && hunk patch \"$patch_file\""
else
  mode="diff"
  # ベースブランチは origin/HEAD -> gh -> main/master の順で解決する
  base_ref="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -z "$base_ref" ]]; then
    default_branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)"
    [[ -n "$default_branch" ]] && base_ref="origin/$default_branch"
  fi
  if [[ -z "$base_ref" ]]; then
    for b in main master; do
      if git show-ref --verify --quiet "refs/remotes/origin/$b"; then
        base_ref="origin/$b"
        break
      fi
    done
  fi
  [[ -n "$base_ref" ]] || die "ベースブランチを解決できない。PR 番号を指定するか origin/HEAD を設定すること"
  # 未 rebase のブランチでも余計な差分が混ざらないよう merge-base 起点で比較する。
  # working tree との比較なので、未コミット・未追跡の変更もレビュー対象に入る
  merge_base="$(git merge-base "$base_ref" HEAD)" || die "merge-base を解決できない ($base_ref...HEAD)"
  tab_label="review:${base_ref#origin/}..${branch_short}"
  target_desc="${base_ref}...${branch_short} (working tree 含む)"
  # --watch でコード変更を diff へ自動反映する (patch モードの PR レビューでは使えない)
  hunk_cmd="hunk diff --watch $merge_base"
fi

# workspace 名は git-wt hook と同じ規約: メイン worktree のディレクトリ名 ('.' -> '_')。
# パスに空白があっても壊れないよう porcelain 出力から取る
main_root="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
ws_label="$(basename "$main_root" | tr '.' '_')"

# agent 名は herdr の制約 ([a-z][a-z0-9_-]{0,31}) に収める。
# suffix は branch のフルパス基準 (a/fix と b/fix の衝突回避)
agent_suffix="${pr:+pr${pr}}"
[[ -n "$agent_suffix" ]] || agent_suffix="${branch:-detached}"
agent_name="$(printf 'rev-%s-%s' "$repo_name" "$agent_suffix" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"
if (( ${#agent_name} > 32 )); then
  # 単純な切り詰めは似た名前同士で衝突して冪等判定が誤 focus するため hash を付ける
  name_hash="$(printf '%s' "$agent_name" | cksum | awk '{print $1}')"
  agent_name="${agent_name:0:26}-$(printf '%05d' "$((name_hash % 100000))")"
fi
[[ "$agent_name" =~ ^[a-z] ]] || agent_name="r${agent_name:0:31}"

# 同じ repo の workspace があればそこへ tab を足し、なければ規約どおりの名前で作る
ws_id="$(herdr workspace list | jq -r --arg l "$ws_label" '.result.workspaces[] | select(.label == $l) | .workspace_id' | head -1)"
if [[ -z "$ws_id" ]]; then
  ws_id="$(herdr workspace create --cwd "$main_root" --label "$ws_label" --no-focus | jq -r '.result.workspace.workspace_id')"
  [[ -n "$ws_id" ]] || die "workspace 作成に失敗"
fi

# 再実行の冪等性は tab label ではなく live agent 名で判定する。
# herdr は tab label を branch 名で自動上書きするため label は当てにならない
existing_agent_pane="$(herdr agent list | jq -r --arg n "$agent_name" '.result.agents[] | select(.name == $n) | .pane_id' | head -1)"
if [[ -n "$existing_agent_pane" ]]; then
  herdr agent focus "$agent_name" >/dev/null
  echo "既存のレビュー agent $agent_name (pane $existing_agent_pane) に focus した。作り直す場合は先にその tab を閉じること"
  exit 0
fi

created="$(herdr tab create --workspace "$ws_id" --cwd "$repo" --label "$tab_label" --focus)"
tab_id="$(jq -r '.result.tab.tab_id' <<<"$created")"
hunk_pane="$(jq -r '.result.root_pane.pane_id' <<<"$created")"
[[ -n "$tab_id" && -n "$hunk_pane" ]] || die "tab 作成に失敗: $created"
cleanup_tab_id="$tab_id"

# ratio は first-child (分割元 = hunk 側) の割合。hunk 2/3 : agent 1/3
agent_pane="$(herdr pane split "$hunk_pane" --direction right --ratio 0.67 --cwd "$repo" --no-focus | jq -r '.result.pane.pane_id')"
[[ -n "$agent_pane" ]] || die "pane split に失敗"

# split 直後はシェルがプロンプトに達しておらず agent_pane_busy になるため再試行する。
# agent start 自体はエージェントの起動完了までブロックするので、この待ち時間が
# hunk 側 pane のシェル起動待ちも兼ねる (hunk の起動はこの後に回す)
started=""
for _ in $(seq 1 20); do
  if out="$(herdr agent start "$agent_name" --kind claude --pane "$agent_pane" 2>&1)"; then
    started=1
    break
  fi
  grep -q agent_pane_busy <<<"$out" || die "agent start に失敗: $out"
  sleep 0.5
done
[[ -n "$started" ]] || die "agent 用 pane のシェルが起動しない: $out"

# 起動前の hunk セッション一覧を控えておき、後で新規セッション ID を特定する。
# 同じ repo の古いセッションが残っていると --repo 指定ではそちらを掴んでしまうため
sessions_before="$(hunk session list --json 2>/dev/null | jq -r '.sessions[].sessionId' 2>/dev/null || true)"

# agent start の入力注入が hunk 側 pane に紛れることがあるため、
# 起動前に入力行を掃除し、起動後は hunk プロセスの存在まで検証する
start_hunk() {
  herdr pane send-keys "$hunk_pane" ctrl+c ctrl+u >/dev/null 2>&1 || true
  herdr pane run "$hunk_pane" "$hunk_cmd" >/dev/null
  for _ in $(seq 1 10); do
    if herdr pane process-info --pane "$hunk_pane" | jq -e '.result.process_info.foreground_processes[]? | select(.name == "hunk")' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}
start_hunk || start_hunk || die "hunk の起動を確認できない (pane $hunk_pane)"

# 今回の pane が張った hunk セッション ID を特定する (取れなければ --repo 指定に fallback)。
# 待機中に別の場所で hunk が開かれても誤って掴まないよう cwd でも絞り込む
hunk_session=""
for _ in $(seq 1 10); do
  hunk_session="$(hunk session list --json 2>/dev/null \
    | jq -r --arg cwd "$repo" '.sessions[] | select(.cwd == $cwd) | .sessionId' 2>/dev/null \
    | grep -vxF -f <(printf '%s\n' "$sessions_before") | head -1 || true)"
  [[ -n "$hunk_session" ]] && break
  sleep 0.5
done
if [[ -n "$hunk_session" ]]; then
  sess_sel="$hunk_session"
else
  # プロンプトへそのまま埋め込まれるため、空白入りパスでも壊れないようクォート込みにする
  sess_sel="--repo \"${repo}\""
fi

if [[ "$mode" == "pr" ]]; then
  intent_step="1. \`gh pr view ${pr}\` で PR の意図・説明を把握する"
  closing="4. 最後に総評 (重要な指摘・マージ可否の所感) を短く報告する"
else
  intent_step="1. \`git log --oneline ${merge_base}..HEAD\` と diff 全体から変更の意図を把握する (PR 作成前のセルフレビュー)"
  closing="4. 最後に総評 (重要な指摘・PR を作る前に直すべき点) を短く報告する"
fi

prompt="${target_desc} (${repo_name}) のコードレビューをしてください。左の pane で \`${hunk_cmd}\` の hunk セッションが開いています。

手順:
${intent_step}
2. hunk-review skill を使い、\`hunk session review ${sess_sel} --json\` で diff の構造を確認する。内容 (ファイル一覧) が今回のレビュー対象と明らかに食い違う場合は \`hunk session list\` で正しいセッションを選び直すこと
3. レビューコメントを \`hunk session comment apply ${sess_sel} --stdin\` でまとめてインラインコメントとして追加する
${closing}

コメントは実害のある指摘・設計上の懸念・見落としやすい点に絞り、全 hunk に機械的に付けないこと。"

herdr agent prompt "$agent_name" "$prompt" >/dev/null
cleanup_tab_id=""

# レビュー対象が一目でわかるよう tab をラベル付けする。pane 起動中は worktree 統合の
# 自動タイトル (branch 名) に上書きされるため、起動が落ち着いたこの時点で行う
herdr tab rename "$tab_id" "$tab_label" >/dev/null 2>&1 || true

cat <<EOF
レビュー tab を作成した:
  workspace:      $ws_id ($ws_label)
  tab:            $tab_id ($tab_label)
  hunk pane:      $hunk_pane ($hunk_cmd)
  hunk session:   ${hunk_session:-"(ID 特定失敗: --repo で fallback)"}
  agent:          $agent_name (pane $agent_pane, レビュー実行中)
対象: $target_desc
進捗確認: herdr agent get $agent_name / herdr agent read $agent_name --source recent-unwrapped --lines 80
EOF
