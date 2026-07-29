# vcs.yazi ユーザーマニュアル

`vcs.yazi`は、Yaziのファイル一覧へGit／SVNの状態を表示し、Phase 2の共通操作と
Phase 3のGit操作を提供します。対応Yaziは26.5.6以降です。

## インストールと設定

`vcs.yazi`をYaziのpluginsディレクトリへ配置し、fetcherを登録します。

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

```lua
require("vcs"):setup({
  runner = { timeout_ms = 30000 },
  git = {
    push = { default_remote = "origin", set_upstream_if_missing = true },
    branch = { show_remote = true, validate_name = true, allow_force_delete = false },
    switch = { auto_track_remote = true, auto_stash = false, allow_discard_changes = false },
  },
})
```

## キー操作

`v`はYaziのvisual modeと衝突するため、`<C-g>`を使います。

```toml
[[mgr.prepend_keymap]]
on = [ "<C-g>", "s" ]
run = "plugin vcs -- status"
desc = "Refresh VCS status"
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

`branch`では`list`／`create`／`create-switch`／`rename`／`delete`を入力して操作を選びます。
操作対象は既存のPhase2操作と同じく、選択、hover、現在ディレクトリの順です。

## Git操作の安全仕様

Pushはcurrent branchとupstreamを確認します。upstreamがなければremoteを選び、
`git push --set-upstream <remote> <branch>`を実行します。認証入力のためPush中はYaziの
端末を隠し、Gitの標準入出力を継承します。

Branch名は`@`／`-`始まりを拒否し、`git check-ref-format --branch`で検証します。
削除は`git branch -d`固定で、現在Branch・remote Branch・Force Deleteは対象外です。
Switchはlocal Branchまたはremote tracking Branchへ切り替えます。自動stash、強制Switch、
自動Discardは行いません。成功後はstatusを再fetchします。

## 状態と制約

状態記号は`C` conflict、`!` missing、`D` deleted、`R` replaced/renamed、`M` modified、
`P` property modified、`A` added、`?` untracked、`L` locked、`X` external、`I` ignoredです。
実YaziのUI・認証入力、Windows／WSL、SVN CLI、SVN external等は別途確認が必要です。
外部Diff／LogとWindows GUI連携はPhase 4です。

## テスト

```bash
cd vcs.yazi
lua tests/run.lua
```

Phase3のGitローカルbare repository結合テストを含みます。
