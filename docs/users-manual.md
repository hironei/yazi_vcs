# vcs.yazi ユーザーマニュアル

`vcs.yazi`は、Yaziのファイル一覧へGit／SVNの状態を表示し、共通操作、Git操作、外部Diff／Logを提供します。対応Yaziは26.5.6以降です。

## インストールと設定

プラグインを配置して`ya pkg add`で登録し、以下のfetcherを設定します。fetcher登録を省略すると状態表示は一切動作しません。

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
  path = { external_style = "auto" },
  diff = {
    git_external = { command = "git", args = { "difftool", "--no-prompt", "--", "{targets}" }, interactive = true },
  },
  log = {
    git_external = { command = "lazygit", args = {}, interactive = true },
  },
})
```

## キー操作

```toml
[[mgr.prepend_keymap]]
on = [ "<C-g>", "d" ]
run = "plugin vcs -- diff"
desc = "VCS diff"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "D" ]
run = "plugin vcs -- diff --external"
desc = "External VCS diff"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "l" ]
run = "plugin vcs -- log"
desc = "VCS log"
[[mgr.prepend_keymap]]
on = [ "<C-g>", "L" ]
run = "plugin vcs -- log --external"
desc = "External VCS log"
```

`update`、`commit`、`discard`、Gitの`push`／`branch`／`switch`も同様に`plugin vcs -- <action>`で呼び出せます。操作対象は選択、hover、現在ディレクトリの順です。

## 外部Diff／Log

`--external`は設定されたVCS別外部コマンドを起動します。未設定の場合は実行せず通知します。引数は配列として実行され、`{root}`、`{file}`、`{targets}`、`{revision}`を展開できます。`{targets}`は複数対象を個別の引数に展開します。

- `interactive = true`: pager、CLI、lazygit、tigなど。Yaziを隠して終了を待ちます。
- `interactive = false`: TortoiseProc等のGUI。Yaziを占有せず、終了を待ちません。
- `path_style = "native"`: 変換しない。
- `path_style = "windows"`: 外部GUI用にWindows形式へ変換する。
- `path_style`省略時は`path.external_style`を使用し、`auto`のWSLでは`wslpath -w`、Git Bashでは`cygpath -w`を試します。

Gitの`difftool`は`diff.tool`等のGit設定が必要です。SVNの`--diff-cmd`は固定形式でラッパーを呼ぶため、[`examples/svn-difft-wrapper.sh`](../examples/svn-difft-wrapper.sh)を使用できます。

## 安全性と性能

コマンドは引数配列で実行します。Force Push／Force Delete、自動stash、強制Switch、未追跡ファイルの自動削除は行いません。statusは表示中のパスを対象にし、Gitへ`--no-optional-locks`を付けて別端末の操作とindex lockが衝突しにくい構成です。

## 状態と制約

状態記号は`C` conflict、`!` missing、`D` deleted、`R` replaced/renamed、`M` modified、`P` property modified、`A` added、`?` untracked、`L` locked、`X` external、`I` ignoredです。

実Yazi UI・認証入力、Windows GUI、WSL／Git Bash、SVN実CLIは別途確認が必要です。

## テスト

```bash
cd vcs.yazi
lua tests/run.lua
luac -p *.lua tests/*.lua
```
