# vcs.yazi

Git／SVNの状態とリポジトリ位置表示、Phase 2の共通操作、Phase 3のGit操作、Phase 4の外部Diff／Log連携を提供するYaziプラグインです。status bar右側にGitの現在branch、または現在ホバー中のファイル／ディレクトリ（ホバー対象がなければcwd）のSVN URLを表示します。

Phase 4の操作:

- CLI Diff／Log: `plugin vcs -- diff`、`plugin vcs -- log`
- 外部Diff／Log: `plugin vcs -- diff --external`、`plugin vcs -- log --external`
- クリップボード: `plugin vcs -- copy-url`、`plugin vcs -- copy-url-revision`
- クリップボード対象は選択対象（複数選択時は先頭）で、SVNはURL、Gitは`branch/root-relative-path`形式です
- TUIは`interactive = true`で`ui.hide()`配下、GUIは`interactive = false`で非占有起動
- WSLの`wslpath -w`、Git Bashの`cygpath -w`による外部GUIパス変換

外部コマンドは`diff.git_external`／`diff.svn_external`／`log.git_external`／`log.svn_external`へ、`command`と`args`を配列で設定します。`{root}`、`{file}`、`{targets}`、`{revision}`を使用できます。`{targets}`は対象ごとに別引数へ展開されます。

SVNの`--diff-cmd`へdifftastic等を接続する例は[`../examples/svn-difft-wrapper.sh`](../examples/svn-difft-wrapper.sh)を参照してください。

VCS操作の対象は、selectedがあればselected、なければcwdです。hoveredだけでは対象を変更しません。cwdがVCS外でも、VCSリポジトリのディレクトリをselectedすればそのリポジトリを操作できます。異なるリポジトリを複数selectedした操作は拒否します。未selectedのAdd／Commit／Discardはcwd配下を広く対象にし得るため、対象範囲を表示してtyped confirmationを要求します。既存のPush・Branch・Switchの安全方針、CLI操作の失敗通知、成功後refreshも維持します。実Yazi UI、Windows GUI、WSL／Git Bash、SVN実CLIは手動確認が必要です。

## VCS Changes View

`plugin vcs -- changes` opens the resolved repository's changed files in Yazi's native Search View. It reuses the Git/SVN status parser, includes untracked files, excludes clean and ignored files, and keeps deleted paths selectable with synthetic metadata when the physical file is gone.

Search URLs are normalized to physical paths before VCS detection or CLI execution. In the Changes View, Diff, Log, Add, Commit, and Discard use only explicit selections. An empty selection does not fall back to cwd or the repository. Git untracked Diff is rendered as an all-added no-index diff; untracked files are excluded from Git Log with a notification.

## VCS Log Preview

Add the following user-defined key binding to show a temporary log notification:

```toml
[[mgr.prepend_keymap]]
on = [ "g", "v", "v" ]
run = "plugin vcs -- log-preview"
desc = "Show VCS log notification"
```

The action reads the currently hovered file or directory and shows a
multi-line notification for eight seconds with up to five newest Git or SVN
entries. It does not alter the Preview area and does not refresh when the
cursor moves; invoke it again for another item. The existing `g v p` Push and
`g v l` CLI Log bindings remain unchanged.

No custom previewer registration is required. An old catch-all previewer rule
for `run = "vcs"` remains safe because the plugin delegates it to the normal
Yazi previewer.

To show the latest five entries in a selectable Spot, add a separate manager
binding and route Spot's Tab through the plugin:

```toml
[[mgr.prepend_keymap]]
on = [ "g", "v", "s" ]
run = "plugin vcs -- log-spot"
desc = "Show VCS log in Spot"

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

Temporary VCS Spotters for files and directories are registered dynamically at
the front of the Spotter list and remain registered while the VCS Spot is
active, allowing the standard Spot `h`/`l` swipe to re-render the log for the
new hovered item. The table has `Date`, `Revision`, and `Message` columns and
supports the standard Spot row navigation keys (`j`/`k`, Up/Down). The
documented movement bindings keep the selected row synchronized for `c v r`
and `c v m`, which copy the selected row's revision and message respectively.
Tab while the VCS table is visible opens the normal Spot for the same item. Esc,
C-[, and C-c close the VCS Spot and clean up the temporary registrations. When
the normal Spot is visible, Tab keeps its default close behavior. Yazi 26.8.15
or newer is required for the dynamic Spotter API; no permanent catch-all
Spotter is added.
