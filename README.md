# yazi_vcs

Yaziのファイル一覧へGit／Subversionの状態を表示し、共通操作、Git操作、外部Diff／Log連携を提供する`vcs.yazi`プラグインです。

## 対応環境

- Yazi 26.5.6以降
- Git 2.30以降、SVN 1.9以降
- Linux、macOS、Windows、Git Bash、WSL

## インストール

プラグインを配置して`ya pkg add`で登録し、fetcherを必ず設定します。fetcher登録を省略すると状態表示は動作しません。

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

`init.lua`では`require("vcs"):setup()`を呼びます。既定のstatus取得は表示中のファイルだけを対象にし、Gitへ`--no-optional-locks`を渡します。

## キー設定

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

既存の`update`、`commit`、`discard`、Gitの`push`／`branch`／`switch`も利用できます。`v`はYaziのvisual modeと衝突するため、例では`<C-g>`を使います。

## 外部Diff／Log設定

外部設定はコマンド名と引数配列を分離します。使用できるプレースホルダーは`{root}`、`{file}`、`{targets}`、`{revision}`です。`{targets}`だけは1つの引数として記述し、対象ごとに安全に展開されます。

```lua
require("vcs"):setup({
  path = { external_style = "auto" }, -- "auto" | "native" | "windows"
  diff = {
    git_external = {
      command = "git",
      args = { "difftool", "--no-prompt", "--", "{targets}" },
      interactive = true,
      path_style = "native",
    },
    svn_external = {
      command = "svn",
      args = { "diff", "--diff-cmd", "svn-difft-wrapper", "--", "{targets}" },
      interactive = true,
    },
  },
  log = {
    git_external = { command = "lazygit", args = {}, interactive = true },
    svn_external = {
      command = "TortoiseProc.exe",
      args = { "/command:log", "/path:{file}" },
      interactive = false,
      path_style = "windows",
    },
  },
})
```

`interactive = true`はYaziを隠して端末を占有するTUI／CLI向けです。`interactive = false`はGUIを待たずに起動します。`git difftool`はGit側の`diff.tool`等の設定を必要とし、プラグインは設定しません。

SVNの`--diff-cmd`はSVN固有の`-u -L label1 -L label2 file1 file2`形式で呼び出されるため、difftastic等へ渡すには同梱の[`examples/svn-difft-wrapper.sh`](examples/svn-difft-wrapper.sh)のようなラッパーを使います。

## Windows／WSL／Git Bash

VCS CLIへ渡すパスは実行環境のnative形式です。外部GUIの絶対パスは`path_style = "windows"`、または`external_style = "auto"`のWSL環境で`wslpath -w`、Git Bashで`cygpath -w`を利用して変換します。変換ツールが利用できない場合は元のパスを渡し、デバッグログへ記録します。

## 安全性

コマンドは引数配列で実行し、shell文字列連結を行いません。Force Push、Force Delete、自動stash、強制Switch、未追跡ファイルの自動削除は実行しません。外部コマンドの失敗は通知し、認証情報をログへ出力しません。

## 検証

```bash
cd vcs.yazi
lua tests/run.lua
luac -p *.lua tests/*.lua
```

Lua単体テスト、Gitローカルbare repository結合テスト、外部設定展開テストを含みます。実Yazi UI、認証入力、Windows GUI、WSL／Git Bashの実環境、SVN実CLIは別途確認が必要です。
