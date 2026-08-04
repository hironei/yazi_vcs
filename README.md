# yazi_vcs

Yaziのファイル一覧へGit／Subversionの状態を表示し、共通操作、Git操作、外部Diff／Log連携を提供する`vcs.yazi`プラグインです。

## 対応環境

- Yazi 26.5.6以降
- Git 2.30以降、SVN 1.9以降
- Linux、macOS、Windows、Git Bash、WSL

## インストール

このリポジトリは、ルート直下の`vcs.yazi/`がYaziプラグイン本体です。Yaziのパッケージ管理を使う場合は、リポジトリ全体ではなくこのサブディレクトリを指定します。

```bash
ya pkg add hironei/yazi_vcs:vcs
```

これにより、通常は次の場所へ`vcs.yazi`が配置され、`package.toml`も更新されます。`package.toml`は手で編集せず、以後の更新も`ya pkg`で行ってください。

| OS | Yaziの設定ディレクトリ |
| --- | --- |
| Linux／macOS／WSL | `~/.config/yazi/` |
| Windows | `%AppData%\yazi\config\` |

`YAZI_CONFIG_HOME`を設定している場合は、そのディレクトリが代わりに使われます。以下ではこの場所を`<YAZI_CONFIG_HOME>`と表記します。パッケージ管理を使わず手動で配置する場合は、リポジトリ内の`vcs.yazi/`ディレクトリを`<YAZI_CONFIG_HOME>/plugins/vcs.yazi/`へコピーしてください。

インストール後は、次の3ファイルへ設定を追加します。既存の内容は削除せず、各ファイルの既存の設定に追記してください。

```text
<YAZI_CONFIG_HOME>/
├── package.toml  # ya pkg addが更新する管理ファイル
├── yazi.toml    # status表示用fetcher
├── keymap.toml  # キー割り当て（必要な場合）
├── init.lua     # プラグイン初期化
└── plugins/
    └── vcs.yazi/  # ya pkg addが配置するプラグイン本体
```

### 1. `yazi.toml`へfetcherを追加する

`<YAZI_CONFIG_HOME>/yazi.toml`に、次の2ブロックを追加します。これを省略すると、Git／SVNの状態表示は動作しません。

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

### 2. `init.lua`でプラグインを初期化する

`<YAZI_CONFIG_HOME>/init.lua`に、次の1行を追加します。既存の`init.lua`がある場合は、既存のコードを残したまま追記してください。

```lua
require("vcs"):setup()
```

これで既定値が有効になります。既定のstatus取得は表示中のファイルだけを対象にし、Gitへ`--no-optional-locks`を渡します。外部Diff／Logなどを使う場合の追加設定は、後述の[外部Diff／Log設定](#外部difflog設定)に記載しています。

### 3. Yaziを再起動する

設定ファイルを保存したらYaziをいったん終了して再起動します。ファイル一覧でGit／SVN管理下のファイルに状態記号が表示されれば、status表示のセットアップは完了です。

## キー設定

`<YAZI_CONFIG_HOME>/keymap.toml`に、使いたいキー割り当てを追加します。以下は`Ctrl-g`を先頭にした例です。既存のキーと衝突する場合は、`on`のキー列を変更してください。

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

外部設定は`<YAZI_CONFIG_HOME>/init.lua`の`require("vcs"):setup({ ... })`へ追加します。すでに`require("vcs"):setup()`を書いている場合は、次の例で置き換えてください（`require`を2回書く必要はありません）。コマンド名と引数配列を分離し、使用できるプレースホルダーは`{root}`、`{file}`、`{targets}`、`{revision}`です。`{targets}`だけは1つの引数として記述し、対象ごとに安全に展開されます。

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
