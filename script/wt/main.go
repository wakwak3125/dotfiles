// wt: git worktree ヘルパー（tmux 統合付き）の標準コマンド版。
// zsh/functions/wt の置き換え。シェル関数ではないため cwd 変更は行わない
// （元の関数もシェル cwd を変更していないので機能差はない）。
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

const usageText = `使い方: wt [-s] <command> [args]

オプション:
  -s, --silent            tmux 操作をスキップ（ブランチ・worktree 操作のみ実行）

コマンド:
  add <branch>            既存ブランチの worktree を作成
  add -b <branch> [base]  新しいブランチを作成して worktree を追加（base 省略時は HEAD）
  rm <branch|.>           worktree を削除（. で現在の worktree）
  rm -b <branch|.>        worktree とブランチを削除（. で現在の worktree）
  list                    worktree 一覧を表示
  prune                   リモート同期 + worktree の整理
  clean                   リモート同期 + マージ済みブランチ削除 + worktree の整理
`

type repoInfo struct {
	root        string
	worktreeDir string
	tmuxSession string
	inTmux      bool
}

func main() {
	silent := false
	args := os.Args[1:]

	for len(args) > 0 && (args[0] == "-s" || args[0] == "--silent") {
		silent = true
		args = args[1:]
	}

	if len(args) == 0 {
		fmt.Print(usageText)
		return
	}

	cmd := args[0]
	args = args[1:]

	if err := ensureGitRepo(); err != nil {
		fail(err)
	}
	ri, err := loadRepoInfo()
	if err != nil {
		fail(err)
	}

	var runErr error
	switch cmd {
	case "add":
		runErr = cmdAdd(args, ri, silent)
	case "rm", "remove":
		runErr = cmdRm(args, ri, silent)
	case "list", "ls":
		runErr = runGit("worktree", "list")
	case "prune":
		runErr = cmdPrune()
	case "clean":
		runErr = cmdClean(ri, silent)
	default:
		fmt.Print(usageText)
		return
	}
	if runErr != nil {
		fail(runErr)
	}
}

func fail(err error) {
	if msg := err.Error(); msg != "" {
		fmt.Fprintln(os.Stderr, msg)
	}
	os.Exit(1)
}

func ensureGitRepo() error {
	c := exec.Command("git", "rev-parse", "--is-inside-work-tree")
	c.Stderr = io.Discard
	if err := c.Run(); err != nil {
		return errors.New("エラー: git リポジトリではありません")
	}
	return nil
}

func loadRepoInfo() (*repoInfo, error) {
	out, err := exec.Command("git", "worktree", "list").Output()
	if err != nil {
		return nil, fmt.Errorf("エラー: git worktree list に失敗しました: %w", err)
	}
	first := strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]
	fields := strings.Fields(first)
	if len(fields) == 0 {
		return nil, errors.New("エラー: メインの worktree を特定できません")
	}
	root := fields[0]
	name := filepath.Base(root)
	return &repoInfo{
		root:        root,
		worktreeDir: filepath.Join(filepath.Dir(root), "worktree", name),
		tmuxSession: strings.ReplaceAll(name, ".", "_"),
		inTmux:      os.Getenv("TMUX") != "",
	}, nil
}

// ----- add -----

func cmdAdd(args []string, ri *repoInfo, silent bool) error {
	createBranch := false
	var branchName, baseBranch string
	for len(args) > 0 {
		switch args[0] {
		case "-b", "--branch":
			createBranch = true
			args = args[1:]
		default:
			if branchName == "" {
				branchName = args[0]
			} else {
				baseBranch = args[0]
			}
			args = args[1:]
		}
	}

	if branchName == "" {
		fmt.Fprintln(os.Stderr, "使い方: wt add [-b] <branch> [base]")
		fmt.Fprintln(os.Stderr, "  -b, --branch  新しいブランチを作成")
		fmt.Fprintln(os.Stderr, "  base          ベースブランチ（省略時は現在の HEAD）")
		return errors.New("")
	}

	dirName := branchBasename(branchName)
	worktreePath := filepath.Join(ri.worktreeDir, dirName)
	if err := os.MkdirAll(ri.worktreeDir, 0o755); err != nil {
		return err
	}

	var gitArgs []string
	if createBranch {
		gitArgs = []string{"worktree", "add", "-b", branchName, worktreePath}
		if baseBranch != "" {
			gitArgs = append(gitArgs, baseBranch)
		}
	} else {
		gitArgs = []string{"worktree", "add", worktreePath, branchName}
	}
	if err := runGit(gitArgs...); err != nil {
		return err
	}

	if silent || !ri.inTmux {
		return nil
	}
	if st, err := os.Stat(worktreePath); err != nil || !st.IsDir() {
		return nil
	}

	target := ri.tmuxSession + ":" + dirName
	if !tmuxHasSession(ri.tmuxSession) {
		_ = runTmux("new-session", "-d", "-s", ri.tmuxSession, "-c", worktreePath, "-n", dirName)
		_ = runTmux("switch-client", "-t", target)
		return nil
	}
	_ = runTmux("new-window", "-t", ri.tmuxSession, "-n", dirName, "-c", worktreePath)
	if tmuxDisplay("#S") != ri.tmuxSession {
		_ = runTmux("switch-client", "-t", target)
	} else {
		_ = runTmux("select-window", "-t", target)
	}
	return nil
}

// ----- rm -----

func cmdRm(args []string, ri *repoInfo, silent bool) error {
	deleteBranch := false
	var branchName string
	for len(args) > 0 {
		switch args[0] {
		case "-b", "--branch":
			deleteBranch = true
			args = args[1:]
		default:
			branchName = args[0]
			args = args[1:]
		}
	}

	if branchName == "" {
		fmt.Fprintln(os.Stderr, "使い方: wt rm [-b] <branch|.>")
		fmt.Fprintln(os.Stderr, "  -b, --branch  ブランチも削除")
		fmt.Fprintln(os.Stderr, "  .             現在の worktree を対象にする")
		return errors.New("")
	}

	if branchName == "." {
		cur, err := gitOutput("rev-parse", "--show-toplevel")
		if err != nil {
			return errors.New("エラー: 現在の worktree を取得できません")
		}
		if cur == ri.root {
			return errors.New("エラー: メインの worktree では実行できません")
		}
		br, err := gitOutput("symbolic-ref", "--short", "HEAD")
		if err != nil || br == "" {
			return errors.New("エラー: 現在のブランチを取得できません")
		}
		branchName = br
	}

	dirName := branchBasename(branchName)
	worktreePath := filepath.Join(ri.worktreeDir, dirName)
	if st, err := os.Stat(worktreePath); err != nil || !st.IsDir() {
		return fmt.Errorf("エラー: worktree '%s' が見つかりません", worktreePath)
	}

	target := ri.tmuxSession + ":" + dirName
	killWindowAfter := false
	if !silent && ri.inTmux && tmuxHasSession(ri.tmuxSession) {
		if tmuxDisplay("#W") == dirName {
			killWindowAfter = true
		} else {
			_ = runTmux("kill-window", "-t", target)
		}
	}

	if err := runGit("worktree", "remove", worktreePath); err != nil {
		return err
	}

	if deleteBranch {
		if err := exec.Command("git", "branch", "-d", branchName).Run(); err != nil {
			if err2 := runGit("branch", "-D", branchName); err2 != nil {
				return err2
			}
		}
		fmt.Printf("ブランチ '%s' を削除しました\n", branchName)
	}

	if killWindowAfter {
		_ = runTmux("kill-window", "-t", target)
	}
	return nil
}

// ----- prune -----

func cmdPrune() error {
	fmt.Println("リモートを同期中...")
	if err := runGit("fetch", "--prune"); err != nil {
		return err
	}
	fmt.Println("worktree を整理中...")
	if err := runGit("worktree", "prune"); err != nil {
		return err
	}
	fmt.Println("完了")
	return nil
}

// ----- clean -----

type cleanEvent struct {
	kind, status, branch string
}

func cmdClean(ri *repoInfo, silent bool) error {
	fmt.Println("リモートを同期中...")
	if err := runGit("fetch", "--prune"); err != nil {
		return err
	}

	branchWT, err := parseWorktreeBranches()
	if err != nil {
		return err
	}
	targets, err := collectCleanTargets()
	if err != nil {
		return err
	}
	if len(targets) == 0 {
		fmt.Fprintln(os.Stderr, "削除対象のブランチはありません")
		fmt.Println("worktree を整理中...")
		_ = runGit("worktree", "prune")
		fmt.Println("完了")
		return nil
	}

	jobsMax := 4
	if v := os.Getenv("WT_CLEAN_JOBS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			jobsMax = n
		}
	}
	isTTY := isTerminal(os.Stderr)

	// tmux IPC は並列化しても意味がないので先に順次実行する
	if !silent && ri.inTmux && tmuxHasSession(ri.tmuxSession) {
		for _, br := range targets {
			if path := branchWT[br]; path != "" {
				_ = runTmux("kill-window", "-t", ri.tmuxSession+":"+filepath.Base(path))
			}
		}
	}

	events := make(chan cleanEvent, len(targets)*2)
	sem := make(chan struct{}, jobsMax)
	var wg sync.WaitGroup

	for _, br := range targets {
		wg.Add(1)
		go func(branch string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			events <- cleanEvent{kind: "START", branch: branch}
			if path := branchWT[branch]; path != "" {
				if _, err := os.Stat(path); err == nil {
					if err := exec.Command("git", "worktree", "remove", path).Run(); err != nil {
						events <- cleanEvent{kind: "END", status: "SKIP", branch: branch}
						return
					}
				}
			}
			if err := exec.Command("git", "branch", "-d", branch).Run(); err == nil {
				events <- cleanEvent{kind: "END", status: "OK", branch: branch}
				return
			}
			if err := exec.Command("git", "branch", "-D", branch).Run(); err == nil {
				events <- cleanEvent{kind: "END", status: "OK", branch: branch}
				return
			}
			events <- cleanEvent{kind: "END", status: "FAIL", branch: branch}
		}(br)
	}

	progressDone := make(chan struct{})
	go func() {
		inflight := map[string]struct{}{}
		var results []string
		total := len(targets)
		count := 0

		redraw := func() {
			if !isTTY {
				return
			}
			keys := make([]string, 0, len(inflight))
			for k := range inflight {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			list := strings.Join(keys, ", ")
			if list == "" {
				list = "(待機中)"
			}
			fmt.Fprintf(os.Stderr, "\r\033[K  [%d/%d] 処理中: %s", count, total, list)
		}

		for ev := range events {
			switch ev.kind {
			case "START":
				inflight[ev.branch] = struct{}{}
				redraw()
			case "END":
				count++
				delete(inflight, ev.branch)
				switch ev.status {
				case "OK":
					results = append(results, "  ✓ "+ev.branch)
				case "SKIP":
					results = append(results, "  - スキップ（未コミット変更あり）: "+ev.branch)
				case "FAIL":
					results = append(results, "  ✗ ブランチ削除失敗: "+ev.branch)
				}
				redraw()
			}
		}
		if isTTY {
			fmt.Fprint(os.Stderr, "\r\033[K")
		}
		for _, r := range results {
			fmt.Fprintln(os.Stderr, r)
		}
		close(progressDone)
	}()

	doneCh := make(chan struct{})
	go func() {
		wg.Wait()
		close(events)
		close(doneCh)
	}()

	sigCh := make(chan os.Signal, 2)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(sigCh)

	interrupted := false
	select {
	case <-doneCh:
	case <-sigCh:
		interrupted = true
		// 起動済みの git プロセスは続行させ、完了を待ってからクリーンアップする
		<-doneCh
	}
	<-progressDone
	if interrupted {
		fmt.Fprintln(os.Stderr, "中断しました")
		return errors.New("")
	}

	fmt.Println("worktree を整理中...")
	_ = runGit("worktree", "prune")
	fmt.Println("完了")
	return nil
}

func parseWorktreeBranches() (map[string]string, error) {
	out, err := exec.Command("git", "worktree", "list", "--porcelain").Output()
	if err != nil {
		return nil, err
	}
	m := map[string]string{}
	var path, branch string
	flush := func() {
		if path != "" && branch != "" {
			m[branch] = path
		}
		path, branch = "", ""
	}
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "worktree "):
			path = strings.TrimPrefix(line, "worktree ")
		case strings.HasPrefix(line, "branch refs/heads/"):
			branch = strings.TrimPrefix(line, "branch refs/heads/")
		case line == "":
			flush()
		}
	}
	flush()
	return m, nil
}

func collectCleanTargets() ([]string, error) {
	seen := map[string]struct{}{}
	var out []string
	add := func(b string) {
		b = strings.TrimSpace(b)
		if b == "" {
			return
		}
		if _, ok := seen[b]; ok {
			return
		}
		seen[b] = struct{}{}
		out = append(out, b)
	}
	isBase := func(b string) bool {
		return b == "main" || b == "master" || b == "develop"
	}

	for _, base := range []string{"main", "master", "develop"} {
		if err := exec.Command("git", "show-ref", "--verify", "--quiet", "refs/heads/"+base).Run(); err != nil {
			continue
		}
		mout, err := exec.Command("git", "branch", "--merged", base).Output()
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(strings.NewReader(string(mout)))
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(strings.TrimSpace(line), "*") {
				continue
			}
			b := strings.TrimSpace(strings.TrimLeft(line, "+ "))
			if isBase(b) {
				continue
			}
			add(b)
		}
	}

	gout, err := exec.Command("git", "branch", "-vv").Output()
	if err != nil {
		return out, nil
	}
	scanner := bufio.NewScanner(strings.NewReader(string(gout)))
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.Contains(line, ": gone]") {
			continue
		}
		fields := strings.Fields(strings.TrimLeft(line, "* +"))
		if len(fields) == 0 {
			continue
		}
		b := fields[0]
		if isBase(b) {
			continue
		}
		add(b)
	}
	return out, nil
}

// ----- git / tmux helpers -----

func runGit(args ...string) error {
	c := exec.Command("git", args...)
	c.Stdout = os.Stdout
	c.Stderr = os.Stderr
	return c.Run()
}

func gitOutput(args ...string) (string, error) {
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func runTmux(args ...string) error {
	c := exec.Command("tmux", args...)
	c.Stderr = io.Discard
	return c.Run()
}

func tmuxHasSession(name string) bool {
	c := exec.Command("tmux", "has-session", "-t", name)
	c.Stderr = io.Discard
	return c.Run() == nil
}

func tmuxDisplay(fmtStr string) string {
	out, err := exec.Command("tmux", "display-message", "-p", fmtStr).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// ----- misc -----

func branchBasename(b string) string {
	if i := strings.LastIndex(b, "/"); i >= 0 {
		return b[i+1:]
	}
	return b
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}
