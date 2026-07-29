# vcs.yazi ユーザーマニュアル

`vcs.yazi`は、Yaziのファイル一覧へGit／SVNの状態を表示し、Phase 2の共通操作を提供します。
対応Yaziは26.5.6以降です。

## インストールと設定

`vcs.yazi`をYaziのpluginsディレクトリへコピーまたはリンクし、fetcherを登録します。

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
  editor = { command = "nvim", args = {}, wait = true },
  pager = { command = "less", args = { "-R" } },
  runner = { timeout_ms = 30000 },
  commit = { git_mode = "paths", allow_empty_message = false },
})
```

fetcher登録がない場合、`setup()`が成功しても状態取得は実行されません。

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
```

操作対象は、選択中の複数ファイル、hover中のファイル、現在ディレクトリの順です。
UpdateはGitで`pull --ff-only`、SVNで`update`を実行します。Diff／LogはCLI出力をpager
（未設定時はeditor）で表示します。

Commitは一時メッセージファイルをeditorで開き、空白・コメントだけのメッセージは実行しません。
Gitの既定`commit.git_mode = "paths"`では確認画面に列挙したパスだけが暗黙stageされます。
`staged`ではstage済み内容だけをコミットします。

Discardは必ず確認し、未追跡・ignoredファイルを除外します。ディレクトリは`revert`のタイプ
確認を要求し、未追跡ファイルの削除は行いません。成功した操作は状態を破棄して再fetchします。

## 状態記号

`C` conflict、`!` missing、`D` deleted、`R` replaced/renamed、`M` modified、`P` property
modified、`A` added、`?` untracked、`L` locked、`X` external、`I` ignoredです。
子孫の状態はディレクトリへ集約されます。

## 制約とトラブルシュート

- Git／SVN CLIがPATHに必要です。
- 実Yaziの端末占有、editor／pager、Windows／WSLの操作は手動確認が必要です。
- SVNのexternal／obstructed／incompleteは実作業コピーで未検証です。
- Git Push、Branch、Switch、外部Diff／LogはPhase 3以降です。

テストは次で実行します。

```bash
cd vcs.yazi
lua tests/run.lua
```
