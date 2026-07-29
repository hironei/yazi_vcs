# yazi_vcs

Yaziのファイル一覧へGit／Subversionの状態を表示し、共通操作とGit操作を提供する
`vcs.yazi`プラグインです。Phase 3ではGit Push、Branch管理、Switchまで実装しています。

## 対応環境

- Yazi 26.5.6以降
- Git 2.30以降、SVN 1.9以降
- Linux、macOS、Windows、WSL

## 設定

fetcher登録は必須です。

```toml
[[plugin.prepend_fetchers]]
id = "vcs"
url = "*"
run = "vcs"
group = "vcs"

[[plugin.prepend_fetchers]]
id = "vcs"
url = "*/"
run = "vcs"
group = "vcs"
```

`init.lua`では`require("vcs"):setup()`を呼びます。Phase 2／3のキー例:

```toml
[[mgr.prepend_keymap]]
on = [ "<C-g>", "u" ]
run = "plugin vcs -- update"
desc = "VCS update"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "c" ]
run = "plugin vcs -- commit"
desc = "VCS commit"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "d" ]
run = "plugin vcs -- diff"
desc = "VCS diff"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "l" ]
run = "plugin vcs -- log"
desc = "VCS log"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "r" ]
run = "plugin vcs -- discard"
desc = "Discard local changes"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "g", "p" ]
run = "plugin vcs -- push"
desc = "Git push"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "g", "b" ]
run = "plugin vcs -- branch"
desc = "Git branches"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "g", "s" ]
run = "plugin vcs -- switch"
desc = "Git switch branch"
```

`branch`は`list`／`create`／`create-switch`／`rename`／`delete`を入力して選びます。
Pushでupstreamが未設定の場合は、設定の`default_remote`または入力したremoteへ
`--set-upstream`付きでPushします。

```lua
require("vcs"):setup({
  runner = { timeout_ms = 30000 },
  git = {
    push = { default_remote = "origin", set_upstream_if_missing = true },
    branch = { validate_name = true, allow_force_delete = false },
    switch = { auto_track_remote = true, auto_stash = false, allow_discard_changes = false },
  },
})
```

## 安全性

Force Push、Force Delete、`git stash`、強制Switchは実行しません。detached HEADからの
Push、現在Branchの削除、remote Branchの削除を拒否します。Branch名は`@`／`-`始まりを
事前拒否したうえで`git check-ref-format --branch`で検証します。

## 検証

```bash
cd vcs.yazi
lua tests/run.lua
```

Phase3のGitローカルbareリポジトリ結合テストを含みます。実YaziのUI、認証入力、Windows／WSL、
SVN CLIは別途確認が必要です。外部Diff／LogとWindows GUI連携はPhase4です。
