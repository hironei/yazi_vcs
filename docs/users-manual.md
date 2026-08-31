# vcs.yazi ユーザーガイド

`vcs.yazi`は、Yaziのファイル一覧へGit／Subversion（SVN）の状態とリポジトリ位置を表示し、共通操作、Git操作、外部Diff／Log連携を提供するプラグインです。対応Yaziは26.8.15以降です。

## インストールと設定場所

### 1. プラグインをインストールする

このリポジトリでは、ルート直下の`vcs.yazi/`がプラグイン本体です。`ya pkg`でインストールする場合は、リポジトリ内のサブディレクトリを指定します。

```bash
ya pkg add hironei/yazi_vcs:vcs
```

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

### 2. OSごとの設定ディレクトリ

| OS | `<YAZI_CONFIG_HOME>` |
| --- | --- |
| Linux／macOS／WSL | `~/.config/yazi/` |
| Windows | `%AppData%\yazi\config\` |

`YAZI_CONFIG_HOME`環境変数を設定している場合は、そのディレクトリが優先されます。以降の`<YAZI_CONFIG_HOME>`は、実際に使用している設定ディレクトリへ読み替えてください。

インストール後の構成は次のようになります。

```text
<YAZI_CONFIG_HOME>/
├── package.toml  # ya pkg addが更新する管理ファイル
├── yazi.toml    # fetcher設定
├── keymap.toml  # キー割り当て
├── init.lua     # プラグイン初期化・詳細設定
└── plugins/
    └── vcs.yazi/  # プラグイン本体
```

`package.toml`と`plugins/vcs.yazi/`は`ya pkg`が管理します。通常、これらを手で編集する必要はありません。Git clone方式では`package.toml`は作成されず、プラグイン本体だけが`plugins/vcs.yazi/`に配置されます。

### 3. `yazi.toml`にfetcherを追加する

`<YAZI_CONFIG_HOME>/yazi.toml`へ、次の2ブロックを追加します。fetcherは表示中のファイルの状態を取得する起動契機です。登録を省略すると、Git／SVNの状態表示は動作しません。

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

### 4. `init.lua`で初期化する

`<YAZI_CONFIG_HOME>/init.lua`へ次の1行を追加します。既存の`init.lua`がある場合は、既存のコードを残したまま追記してください。

```lua
require("vcs"):setup()
```

既定値では、次の設定が有効です。

| 設定 | 既定値 | 内容 |
| --- | --- | --- |
| `detection.priority` | `{ "git", "svn" }` | 同じ場所で両方を検出した場合はGitを優先 |
| `status.order` | `500` | 状態記号を表示する列の順序 |
| `status.aggregate_directories` | `true` | 配下の状態をディレクトリへ集約 |
| `status.ignore_externals` | `true` | SVN externalsを状態取得から除外 |
| `info.enabled` | `true` | status bar右側のGit branch／SVN位置表示 |
| `info.order` | `600` | リポジトリ位置表示の順序 |
| `editor.command` | `"nvim"` | Commitメッセージ編集に使うコマンド |
| `pager.command` | `"less"` | Diff／Log表示に使うコマンド |
| `runner.timeout_ms` | `30000` | 通常のCLI操作のタイムアウト（ミリ秒） |
| `path.external_style` | `"auto"` | 外部コマンドへ渡すパス形式の自動判定 |

より細かく変更する場合は、`init.lua`の`setup`へ次の設定キーを指定します。`update`、`diff.*_cli`、`log.*_cli`の配列は先頭に実行コマンドを含めます。外部コマンドだけは`command`と`args`を分けて指定します。

| 設定キー | 既定値・例 | 内容 |
| --- | --- | --- |
| `signs.modified` など | `"M"` | 状態記号を変更。`conflict`、`missing`、`deleted`、`replaced`、`modified`、`property_modified`、`added`、`untracked`、`locked`、`external`、`ignored`、`clean`を指定可能 |
| `update.git` | `{ "git", "pull", "--ff-only" }` | GitのUpdateコマンド |
| `update.svn` | `{ "svn", "update" }` | SVNのUpdateコマンド |
| `commit.allow_empty_message` | `false` | 空のCommitメッセージを許可するか |
| `commit.git_mode` | `"paths"` | `"paths"`または`"staged"`。Gitで選択パスを暗黙stageするか、stage済み内容を使うか |
| `diff.git_cli` | `{ "git", "diff", "--", "{targets}" }` | GitのCLI Diff |
| `diff.svn_cli` | `{ "svn", "diff", "--", "{targets}" }` | SVNのCLI Diff |
| `log.git_cli` | `git log --decorate --oneline --graph ...` | Gitの対象指定Log |
| `log.svn_cli` | `{ "svn", "log", "--", "{targets}" }` | SVNのCLI Log |
| `discard.recursive_confirm_text` | `"revert"` | Discard（selected／cwdを問わず必ず確認）の確認文字列 |
| `runner.timeout_ms` | `30000` | 通常のCLI操作のタイムアウト。`0`はタイムアウト無効（無期限） |
| `git.push.default_remote` | `"origin"` | upstream未設定時に優先するremote |
| `git.push.set_upstream_if_missing` | `true` | upstream未設定時に`--set-upstream`を許可 |
| `git.branch.show_remote` | `true` | Branch一覧へremote Branchを含める |
| `git.switch.auto_track_remote` | `true` | remote Branchへ切り替える際にlocal tracking Branchを作る |

たとえば、エディタとpagerを変更する場合は、1行の設定を次のように置き換えます。

```lua
-- <YAZI_CONFIG_HOME>/init.lua
require("vcs"):setup({
  editor = { command = "code", args = { "--wait" } },
  pager = { command = "bat", args = { "--paging=always" } },
})
```

設定はマップについて既定値へ深くマージされるため、指定していない項目は既定値のままです。配列（`update.*`、`diff.*_cli`、`log.*_cli`、`editor.args`、`pager.args`）は指定した配列全体で置き換えられ、既定配列の末尾は引き継ぎません。

### 5. Yaziを再起動する

設定ファイルを保存したらYaziをいったん終了して再起動します。GitリポジトリまたはSVN working copy内で、ファイル名の前に状態記号とstatus barのリポジトリ位置が表示されればstatus表示のセットアップは完了です。

## キー割り当て

キー割り当ては`<YAZI_CONFIG_HOME>/keymap.toml`へ追加します。以下は`g`→`v`をVCS用プレフィックスにする一例です。`g`→`v`の後に操作キーを続けて入力します。

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
on = [ "g", "v", "p" ]
run = "plugin vcs -- push"
desc = "Git push"

[[mgr.prepend_keymap]]
on = [ "g", "v", "b" ]
run = "plugin vcs -- branch"
desc = "Git branch"

[[mgr.prepend_keymap]]
on = [ "g", "v", "s" ]
run = "plugin vcs -- switch"
desc = "Git switch"
```

キー列は任意に変更できます。既存のキー割り当てと衝突する場合は、`on`の値を変更してください。

## 対応コマンド一覧

### Git／SVN共通コマンド

操作対象は「選択中の項目 → 現在のディレクトリ」の順で決まります。hover中の項目だけではVCS操作対象は変わりません。cwdがVCS外でも、VCSリポジトリのディレクトリを選択すれば、そのリポジトリを操作できます。statusはYaziが表示中のファイルを対象に自動実行し、Update／Push／Branch／Switchは解決したrepository context全体を操作します。

| Yaziから呼び出すコマンド | Gitで実行されるコマンド | SVNで実行されるコマンド | 内容 |
| --- | --- | --- | --- |
| `plugin vcs -- status` | `git --no-optional-locks -c core.quotePath= status --porcelain=v2 -z --untracked-files=all --ignored=matching -- <paths>` | `svn status --xml --no-ignore --ignore-externals -- <paths>` | statusを再取得。通常はfetcherが自動実行 |
| `plugin vcs -- update` | `git pull --ff-only` | `svn update` | fast-forwardのみのGit pull、またはSVN update。認証入力が必要な場合はYaziを隠して端末入力を引き継ぎます |
| `plugin vcs -- add` | `git add -- <targets>` | `svn add -- <targets>` | 選択対象、または未選択時のcwdをバージョン管理に追加（cwd scopeは確認が必要。Gitはstageも兼ねる） |
| `plugin vcs -- commit` | `git commit --file=<message> -- <selected paths>` | `svn commit --file=<message> -- <selected paths>` | 対象を表示して確認後、エディタでメッセージを入力してCommit。未選択時はcwd scopeを明示 |
| `plugin vcs -- diff` | `git diff -- <targets>` | `svn diff -- <targets>` | CLI Diffをpagerで表示 |
| `plugin vcs -- log` | `git log --decorate --oneline --graph -- <targets>` | `svn log -- <targets>` | CLI Logをpagerで表示 |
| `plugin vcs -- discard` | `git restore -- <targets>` | `svn revert [--depth=infinity] -- <targets>` | ローカル変更を破棄。selected／cwdを問わずtyped confirmationが必要 |

repository root、またはrepository rootをcwdとしているscopeのDiff／Logでは、`.`をpath filterとして渡さずリポジトリ全体を表示します。通常のselected pathやroot以外のcwdでは、そのpathだけを対象にします。

Gitの`commit.git_mode`を`"staged"`へ変更した場合は、Git Commit時にパスを渡さず、あらかじめstage済みの内容をCommitします。既定値は`"paths"`で、選択したパスがGitに暗黙的にstageされます。

Discardでは未追跡ファイル・ignoredファイルを対象外とします。通常のDiscardは`discard`、ディレクトリを再帰的に破棄する場合は、既定で`revert`という文字の入力が必要です。

Addではignoredファイルを対象外とします（`git add`はignoredファイルを`-f`無しでは受け付けず、`svn add`は既定でsvn:ignore対象を無視するため）。除外があった場合は通知します。

`log.git_cli`と`log.svn_cli`は、`{targets}`プレースホルダーを対象パスへ展開して実行します。対象を指定しない場合の表示範囲は、設定したCLIコマンドの引数に従います。

### 外部Diff／Log

次のコマンドは、`init.lua`でVCSごとの外部コマンドを設定した場合だけ実行されます。

| Yaziから呼び出すコマンド | 設定キー | 内容 |
| --- | --- | --- |
| `plugin vcs -- diff --external` | `diff.git_external`／`diff.svn_external` | 差分がある場合に外部Diffツールを起動。差分が無ければ通知 |
| `plugin vcs -- log --external` | `log.git_external`／`log.svn_external` | 外部Logビューアを起動 |

設定例です。`require("vcs"):setup()`をすでに書いている場合は、二重に書かず、この形へ置き換えてください。

```lua
-- <YAZI_CONFIG_HOME>/init.lua
require("vcs"):setup({
  path = { external_style = "auto" }, -- "auto" | "native" | "windows"
  diff = {
    -- Git側でBeyond Compareをdiff.tool=bcとして設定しておくと、
    -- Gitがbcomp.exeを起動して旧版と作業ツリーを比較します。
    git_external = {
      command = "git",
      args = { "difftool", "--no-prompt", "--", "{targets}" },
      interactive = true,
      path_style = "native",
    },
    svn_external = {
      command = "svn",
      args = {
        "diff",
        "--diff-cmd",
        "C:/Program Files/Beyond Compare 5/bcsvn.bat",
        "--",
        "{targets}",
      },
      interactive = true,
      path_style = "windows",
    },
  },
  log = {
    git_external = {
      command = "TortoiseGitProc.exe",
      args = { "/command:log", "/path:{file}" },
      interactive = false,
      path_style = "windows",
    },
    svn_external = {
      command = "TortoiseProc.exe",
      args = { "/command:log", "/path:{file}" },
      interactive = false,
      path_style = "windows",
    },
  },
})
```

Gitの外部DiffをBeyond Compareで開く場合は、先にGitへ`bcomp.exe`を登録します。Windowsの標準的なインストール先は環境に合わせて変更してください。

```bash
git config --global diff.tool bc
git config --global difftool.bc.path "C:/Program Files/Beyond Compare 5/bcomp.exe"
git config --global difftool.prompt false
```

上の`git_external`は`git difftool`を呼び出すため、GitがBeyond Compareを使ってVCSの旧版と作業ツリーを比較します。`bcomp.exe`をプラグインから直接起動する設定は、選択中のパスを開くだけでGitの比較対象を組み立てないため、VCS Diffにはこの`git difftool`経由の設定を使用してください。

SVNの外部Diffでは、SVNが渡す引数をBeyond Compare用に変換する`bcsvn.bat`が必要です。Beyond Compareのインストール先（上の例では`C:/Program Files/Beyond Compare 5/`）に、次の内容で`bcsvn.bat`を作成してください。

```bat
call "%~dp0\bcomp.exe" "%6" /title1=%3 "%7" /title2=%5
IF %errorlevel%==0 goto ZERO
EXIT /B 1
:ZERO
EXIT /B 0
```

SVNの設定例はこのラッパーを`--diff-cmd`で指定しています。インストール先を変更した場合は、`svn_external.args`のパスも同じ場所へ変更してください。

Gitの外部Logは`TortoiseGitProc.exe`のログダイアログを起動します。`TortoiseGitProc.exe`がPATHにない場合は、`command`を実際のインストール先（例: `C:/Program Files/TortoiseGit/bin/TortoiseGitProc.exe`）へ変更してください。

外部設定の項目は次のとおりです。

| 項目 | 内容 |
| --- | --- |
| `command` | 実行するプログラム名 |
| `args` | 引数の配列。shell文字列として連結しない |
| `interactive = true` | Yaziを隠し、CLI／TUIの終了を待つ |
| `interactive = false` | GUIを待たずに起動する |
| `path_style = "native"` | 実行環境のパス形式をそのまま渡す |
| `path_style = "windows"` | Windows形式へ変換して渡す |
| `{root}` | VCSルート |
| `{file}` | selected先頭のpath。selectedがなければcwd |
| `{targets}` | 対象ファイル。対象ごとに別引数へ展開 |
| `{revision}` | Log／Diffで利用できるリビジョン値 |

`path_style`を省略した場合は`path.external_style`を使います。`auto`では、WSLで`wslpath -w`、Git Bashで`cygpath -w`を利用して外部GUI向けのパスへ変換します。

Gitの`difftool`はGit側の`diff.tool`などの設定も必要です。SVNの`--diff-cmd`はSVN固有の`-u -L label1 -L label2 file1 file2`形式で呼び出されるため、difftastic等へ接続する場合は同梱の[`examples/svn-difft-wrapper.sh`](../examples/svn-difft-wrapper.sh)のようなラッパーを使用します。

## Git専用コマンド

SVN working copyでは、次の操作は利用できません。Gitリポジトリ以外で実行すると通知されます。

| Yaziから呼び出すコマンド | 実行されるGitコマンド | 内容 |
| --- | --- | --- |
| `plugin vcs -- push` | `git push` | upstream設定済みの現在ブランチをPush |
| `plugin vcs -- branch list` | `git branch --all ...` | local／remote Branch一覧を表示 |
| `plugin vcs -- branch create` | `git branch <name> [<start>]` | Branchを作成 |
| `plugin vcs -- branch create-switch` | `git switch -c <name> [<start>]` | Branchを作成して切替 |
| `plugin vcs -- branch rename` | `git branch -m [<old>] <new>` | Branch名を変更 |
| `plugin vcs -- branch delete` | `git branch -d <name>` | マージ済みのlocal Branchを安全に削除 |
| `plugin vcs -- switch` | `git switch <name>`／`git switch --track <remote>` | local／remote Branchへ切替 |

`plugin vcs -- branch`のようにsubactionを省略すると、Branch操作の入力を表示します。Branch作成・名称変更・切替では入力値を検証します。現在のBranch、remote Branch、force deleteはこの操作から削除できません。Pushでもforce optionは使用せず、upstream未設定時は`origin`を優先して`--set-upstream`を付けます。remoteが複数ある場合は選択入力を表示します。

## 状態記号

| 記号 | 状態 |
| --- | --- |
| `C` | conflict |
| `!` | missing |
| `D` | deleted |
| `R` | replaced／renamed |
| `M` | modified |
| `P` | property modified（SVN） |
| `A` | added |
| `?` | untracked |
| `L` | locked（SVN） |
| `X` | external（SVN） |
| `I` | ignored |

## 安全性と制約

- コマンドは引数配列で実行し、shell文字列連結を行いません。
- Git Force Push、Force Delete、auto-stash、強制Switchは実行しません。
- 未追跡ファイルを自動削除しません。
- Commitは`commit`、Branch削除は`delete`、Discardは`discard`、再帰的なDiscardは`revert`の入力で確認します。
- Git Pushは認証入力の可能性があるため、通常のタイムアウトを適用せず、Yaziを隠して端末を引き継ぎます。
- Git／SVNのCLI、エディタ、pager、外部Diff／Logツールは別途インストールしてPATHを通してください。
- 実Yazi UI、認証入力、Windows GUI、WSL／Git Bashの実環境、SVN実CLIは別途確認が必要です。

## テスト

```bash
cd vcs.yazi
lua tests/run.lua
luac -p *.lua tests/*.lua
```

Lua単体テスト、Gitローカルbare repository結合テスト、SVN status／操作テスト、外部設定展開テストを含みます。

## VCS Changes View (Issue #42)

Bind `plugin vcs -- changes` to open the current Git or SVN repository's changed paths in Yazi's native Search View:

```toml
[[mgr.prepend_keymap]]
on = [ "g", "v", "C" ]
run = "plugin vcs -- changes"
desc = "Show VCS changes"
```

The view includes modified, added, deleted, replaced, conflicted, and untracked paths. Clean and ignored paths are omitted. Deleted paths remain selectable even when their physical files are missing.

In this view, Diff, Log, Add, Commit, and Discard use only explicitly selected paths. If nothing is selected, the operation reports `No VCS target selected.` instead of operating on cwd or the whole repository. Git untracked Diff is shown as an all-added diff; untracked files have no Git history and are skipped by Log with a notification.
