# yazi_vcs

Yaziのファイル一覧へGit／Subversionの状態を表示し、共通操作を実行する
`vcs.yazi`プラグインです。Phase 2ではStatus MVPに加え、Update、Commit、CLI
Diff、CLI Log、Discardを実装しています。

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

`init.lua`では`require("vcs"):setup()`を呼びます。Phase2のキー例:

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
```

対象は選択中の複数ファイル、hover中のファイル、現在ディレクトリの順です。
Commitは既定で選択パスだけをGitへ渡し、そのパスだけが暗黙stageされます。
`commit.git_mode = "staged"`ではstage済み内容だけをコミットします。Discardは
確認を行い、未追跡・ignoredファイルを削除しません。

```lua
require("vcs"):setup({
  editor = { command = "nvim", args = {}, wait = true },
  pager = { command = "less", args = { "-R" } },
  runner = { timeout_ms = 30000 },
  commit = { git_mode = "paths", allow_empty_message = false },
})
```

## 検証

```bash
cd vcs.yazi
lua tests/run.lua
```

実Yaziの描画、端末占有、エディタ／pager、Windows／WSLの実操作は別途目視確認が必要です。
Git Push、Branch、Switch、外部Diff／LogはPhase 3以降です。

## ドキュメント

- [要件定義](docs/requirements.md)
- [設計書](docs/design.md)
- [ユーザーマニュアル](docs/users-manual.md)
- [TODO](docs/todo.md) / [完了記録](docs/done.md)
