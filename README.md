# yazi_vcs

Yaziのファイル一覧へGit／Subversionの状態とリポジトリ位置を表示し、共通操作、Git操作、外部Diff／Log連携を提供する`vcs.yazi`プラグインです。

## 対応環境

- Yazi 26.8.15以降
- Git 2.30以降、SVN 1.9以降
- Linux、macOS、Windows、Git Bash、WSL

## インストール

このリポジトリは、ルート直下の`vcs.yazi/`がYaziプラグイン本体です。Yaziのパッケージ管理を使う場合は、リポジトリ全体ではなくこのサブディレクトリを指定します。

```bash
ya pkg add hironei/yazi_vcs:vcs
```

これにより、通常は次の場所へ`vcs.yazi`が配置され、`package.toml`も更新されます。`package.toml`は手で編集せず、以後の更新も`ya pkg`で行ってください。

### Git cloneで手動インストールする場合

このリポジトリはルート直下に`vcs.yazi/`を含む構成です。そのため、リポジトリ全体を直接`plugins/vcs.yazi/`へcloneすると、プラグインが`plugins/vcs.yazi/vcs.yazi/`に入ってしまいます。いったん一時ディレクトリへcloneし、その中の`vcs.yazi/`だけを設定ディレクトリへコピーしてください。

Linux／macOS／WSL／Git Bashでは、次を実行します。

```bash
config_dir="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"
tmp_dir="$(mktemp -d)"
git clone --depth 1 https://github.com/hironei/yazi_vcs.git "$tmp_dir/yazi_vcs"
mkdir -p "$config_dir/plugins/vcs.yazi"
cp -R "$tmp_dir/yazi_vcs/vcs.yazi/." "$config_dir/plugins/vcs.yazi/"
rm -rf "$tmp_dir"
```

WindowsのPowerShellでは、次を実行します。

```powershell
$configDir = if ($env:YAZI_CONFIG_HOME) { $env:YAZI_CONFIG_HOME } else { Join-Path $env:APPDATA "yazi\config" }
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("yazi_vcs_" + [Guid]::NewGuid().ToString("N"))
git clone --depth 1 https://github.com/hironei/yazi_vcs.git "$tmpDir\yazi_vcs"
New-Item -ItemType Directory -Force "$configDir\plugins\vcs.yazi" | Out-Null
Copy-Item -Path "$tmpDir\yazi_vcs\vcs.yazi\*" -Destination "$configDir\plugins\vcs.yazi" -Recurse -Force
Remove-Item -LiteralPath $tmpDir -Recurse -Force
```

| OS | Yaziの設定ディレクトリ |
| --- | --- |
| Linux／macOS／WSL | `~/.config/yazi/` |
| Windows | `%AppData%\yazi\config\` |

`YAZI_CONFIG_HOME`を設定している場合は、そのディレクトリが代わりに使われます。以下ではこの場所を`<YAZI_CONFIG_HOME>`と表記します。Git clone方式では`package.toml`は作成されず、プラグイン本体だけが`<YAZI_CONFIG_HOME>/plugins/vcs.yazi/`に配置されます。

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

これで既定値が有効になります。既定のstatus取得は表示中のファイルだけを対象にし、Gitへ`--no-optional-locks`を渡します。status bar右側には、Gitなら`(branch-name)`、SVNなら現在ホバー中のファイル／ディレクトリ（ホバー対象がなければ現在のcwd）のURLを`(svn: https://host/svn/base_url/trunk/file.txt)`のように表示します。VCS操作の対象は、選択ありなら選択した項目、選択なしなら現在のディレクトリです。カーソル位置（hover）だけでは操作対象は変わりません。cwdがVCS外でも、VCSリポジトリのディレクトリを選択すればそのリポジトリを操作できます。外部Diff／Logなどを使う場合の追加設定は、後述の[外部Diff／Log設定](#外部difflog設定)に記載しています。

### 3. Yaziを再起動する

設定ファイルを保存したらYaziをいったん終了して再起動します。ファイル一覧でGit／SVN管理下のファイルに状態記号とstatus barのリポジトリ位置が表示されれば、status表示のセットアップは完了です。Updateは認証入力の可能性があるため、Yaziを一時的に隠して端末を引き継ぎます。

## キー設定

`<YAZI_CONFIG_HOME>/keymap.toml`に、使いたいキー割り当てを追加します。以下は`g`→`v`をVCS用プレフィックスにした例です。既存のキーと衝突する場合は、`on`のキー列を変更してください。

```toml
[[mgr.prepend_keymap]]
on = [ "g", "v", "r" ]
run = "plugin vcs -- status"
desc = "Refresh VCS status"
[[mgr.prepend_keymap]]
on = [ "g", "v", "u" ]
run = "plugin vcs -- update"
desc = "VCS update"
[[mgr.prepend_keymap]]
on = [ "g", "v", "a" ]
run = "plugin vcs -- add"
desc = "VCS add"
[[mgr.prepend_keymap]]
on = [ "g", "v", "c" ]
run = "plugin vcs -- commit"
desc = "VCS commit"
[[mgr.prepend_keymap]]
on = [ "g", "v", "x" ]
run = "plugin vcs -- discard"
desc = "Discard VCS changes"
[[mgr.prepend_keymap]]
on = [ "g", "v", "X" ]
run = "plugin vcs -- delete"
desc = "Delete VCS paths"
[[mgr.prepend_keymap]]
on = [ "g", "v", "d" ]
run = "plugin vcs -- diff"
desc = "VCS diff"
[[mgr.prepend_keymap]]
on = [ "g", "v", "D" ]
run = "plugin vcs -- diff --external"
desc = "External VCS diff"
[[mgr.prepend_keymap]]
on = [ "g", "v", "l" ]
run = "plugin vcs -- log"
desc = "VCS log"
[[mgr.prepend_keymap]]
on = [ "g", "v", "L" ]
run = "plugin vcs -- log --external"
desc = "External VCS log"
[[mgr.prepend_keymap]]
on = [ "g", "v", "v" ]
run = "plugin vcs -- log-preview"
desc = "Show VCS log notification"
[[mgr.prepend_keymap]]
on = [ "g", "v", "s" ]
run = "plugin vcs -- log-spot"
desc = "Show VCS log in Spot"
[[mgr.prepend_keymap]]
on = [ "g", "v", "y" ]
run = "plugin vcs -- copy-url"
desc = "Copy VCS URL"
[[mgr.prepend_keymap]]
on = [ "g", "v", "Y" ]
run = "plugin vcs -- copy-url-revision"
desc = "Copy VCS URL with revision"
[[mgr.prepend_keymap]]
on = [ "g", "v", "p" ]
run = "plugin vcs -- push"
desc = "Git push"
[[mgr.prepend_keymap]]
on = [ "g", "v", "b" ]
run = "plugin vcs -- branch"
desc = "Git branch actions"
[[mgr.prepend_keymap]]
on = [ "g", "v", "w" ]
run = "plugin vcs -- switch"
desc = "Git switch"
[[mgr.prepend_keymap]]
on = [ "g", "v", "R" ]
run = "plugin vcs -- rename"
desc = "Rename a version-controlled path"
[[mgr.prepend_keymap]]
on = [ "m", "v", "m" ]
run = "plugin vcs -- move-other-pane"
desc = "Move items to the other VCS pane"
```

The examples above use `[[mgr.prepend_keymap]]`; set `on` to an unused key
sequence and `run` to the exact `plugin vcs -- ...` action. This covers status,
update, changes, add, commit, discard, delete, CLI and external Diff/Log, log preview,
log Spot, URL copy, Git push/branch/switch, rename, and other-pane move. The
`changes` binding is shown in the [VCS Changes View](#vcs-changes-view) section.
`plugin vcs -- branch` opens a prompt for `list`, `create`, `create-switch`,
`rename`, or `delete`; bind an individual action by adding it after `branch`,
for example `run = "plugin vcs -- branch list"`.

In Spot, add `[[spot.prepend_keymap]]` entries instead. The VCS Log Spot example
below includes every Spot action: switch to the standard Spot, close Spot,
move the selected log row, and copy its revision or message.

`g v R` renames one selected item, or the hovered item when nothing is
selected, in its current parent directory. `m v m` moves selected items (or
the hovered item) into the other pane's current directory and is intended for
the active two-tab layout from [`terrakok/split-tabs.yazi`](https://github.com/terrakok/split-tabs.yazi).
Both actions use `git mv` in a Git working tree or local working-copy
`svn move` in an SVN working copy. All paths must belong to the same VCS root;
SVN operations stay local and do not mutate repository URLs.

`g v X` invokes `plugin vcs -- delete`. It deletes selected files or directories,
or the hovered item when nothing is selected, from the current Git repository or
SVN working copy after a typed `delete` confirmation. The working-copy root,
mixed repositories, and Search View are rejected. Untracked and ignored items
are excluded and are never removed automatically. Git uses literal recursive
`git rm -r`; SVN uses local `svn delete` with literal path handling.

## VCS Log Preview

The optional `plugin vcs -- log-preview` action shows a temporary notification
containing up to the five newest Git or SVN history entries for the currently
hovered file or directory. The notification remains visible for eight seconds
and does not change or replace Yazi's standard Preview. Moving the hover does
not refresh an already displayed notification; press the binding again for the
new item.

No custom previewer registration is required for this action. If an older
`[[plugin.prepend_previewers]]` rule still points `url = "*"` to `run = "vcs"`,
the plugin delegates that preview request to the standard Yazi previewer for
backward compatibility. The existing `g v p` Push and `g v l` CLI Log bindings
are unchanged. Restart Yazi after installing the updated plugin.

To show the same latest-five history in a selectable Spot instead, bind
`plugin vcs -- log-spot` and route Spot's Tab key through the plugin:

```toml
[[spot.prepend_keymap]]
on = "<Tab>"
run = "plugin vcs -- spot-tab"
desc = "Switch VCS log Spot to standard Spot"

[[spot.prepend_keymap]]
on = "<Esc>"
run = "plugin vcs -- spot-close"
desc = "Close VCS log Spot"

[[spot.prepend_keymap]]
on = "<C-[>"
run = "plugin vcs -- spot-close"
desc = "Close VCS log Spot"

[[spot.prepend_keymap]]
on = "<C-c>"
run = "plugin vcs -- spot-close"
desc = "Close VCS log Spot"

[[spot.prepend_keymap]]
on = "j"
run = [ "arrow next", "plugin vcs -- spot-row-next" ]
desc = "Next VCS log row"

[[spot.prepend_keymap]]
on = "<Down>"
run = [ "arrow next", "plugin vcs -- spot-row-next" ]
desc = "Next VCS log row"

[[spot.prepend_keymap]]
on = "k"
run = [ "arrow prev", "plugin vcs -- spot-row-prev" ]
desc = "Previous VCS log row"

[[spot.prepend_keymap]]
on = "<Up>"
run = [ "arrow prev", "plugin vcs -- spot-row-prev" ]
desc = "Previous VCS log row"

[[spot.prepend_keymap]]
on = [ "c", "v", "r" ]
run = "plugin vcs -- spot-copy-revision"
desc = "Copy selected VCS revision"

[[spot.prepend_keymap]]
on = [ "c", "v", "m" ]
run = "plugin vcs -- spot-copy-message"
desc = "Copy selected VCS message"
```

`log-spot` temporarily inserts file and directory VCS Spotters for the active
VCS Spot. The standard Spot `h`/`l` swipe then re-renders the VCS log for the
new hovered item. Use `j`/`k` or Up/Down to select rows; the documented bindings
keep the plugin's copy target synchronized with that selection. `c v r` copies
the selected row's revision and `c v m` copies its message. Tab removes the
temporary state and opens Yazi's normal Spot for the same item. Esc, C-[, and
C-c close the VCS Spot and remove the temporary registrations. When the normal
Spot is active, the same Tab binding preserves the usual close behavior. No
permanent catch-all Spotter is installed, and the existing `log-preview`, `g v p`
Push, and `g v l` CLI Log bindings remain available.

既存の`update`、`add`、`commit`、`discard`、Gitの`push`／`branch`／`switch`も利用できます。`add`は選択対象（複数選択時は選択群、未選択時は現在のディレクトリ）を`git add`／`svn add`でバージョン管理に追加します。未選択のcwd scopeでAddを実行する場合は、配下を広く追加するため`add`の入力確認が必要です。Commitは対象確認後にGit／SVNのネイティブcommit editorを起動するため、変更ファイル一覧などのVCS標準templateが表示されます。Commitのeditorはプラグイン設定ではなく、Git／SVNのユーザー設定で解決されます。`copy-url`は選択対象（複数選択時は先頭、未選択時はcwd）のURL、`copy-url-revision`はURLに対象のリビジョンまたはコミットを付けた値をクリップボードへコピーします。For SVN, percent-encoded UTF-8 path text is decoded for readable Unicode output; encoded URL delimiters, malformed escapes, and Git's `branch/root-relative-path` format are preserved. `g`→`v`の後に操作キーを続けて入力します。

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

`require("vcs"):setup({ ... })`で`runner.audit.enabled = true`を設定すると、
`Runner.run`と`Runner.interactive`の構造化`ya.dbg`監査レコードを出力できます。
既定では無効です。コマンド引数、working directory、取得したstderrのcredential-likeな
値とAuthorizationヘッダー値はマスクされ、対話型コマンドの端末入力と継承された端末出力は記録されません。
確認には`YAZI_LOG=debug`を設定してください。旧`VCS_YAZI_TRACE=1`による操作
トレースは廃止されています。

## 検証

```bash
cd vcs.yazi
lua tests/run.lua
luac -p *.lua tests/*.lua
```

Lua単体テスト、Gitローカルbare repository結合テスト、外部設定展開テストを含みます。実Yazi UI、認証入力、Windows GUI、WSL／Git Bashの実環境、SVN実CLIは別途確認が必要です。

設定のマップは既定値へ深くマージされますが、配列（コマンド引数や`editor.args`／`pager.args`）は指定した配列全体で置き換えられます。非対話型のstatus、Diff、Log、メタデータ取得には`runner.timeout_ms`が適用されます。Git branch／revisionとSVN URLは`info.refresh_ms`（既定5000ミリ秒）で再取得されます。

## VCS Changes View

Run `plugin vcs -- changes` to show the changed files of the resolved Git or SVN working copy in Yazi's native Search View. The view reuses the backend status parser, includes untracked files, excludes clean and ignored files, and keeps deleted files selectable even when they no longer exist on disk.

Search View selections are converted back to physical filesystem paths before any VCS command runs. In this view, Diff, Log, Add, Commit, and Discard operate only on explicitly selected entries; with no selection they show `No VCS target selected.` and never fall back to the repository scope. Git Diff renders untracked files as an all-added no-index diff, while Git Log reports and skips untracked files.

Example key binding:

```toml
[[mgr.prepend_keymap]]
on = [ "g", "v", "C" ]
run = "plugin vcs -- changes"
desc = "Show VCS changes"
```
