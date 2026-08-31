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

Add the following user-defined key binding to toggle the log preview pane:

```toml
[[mgr.prepend_keymap]]
on = [ "g", "v", "v" ]
run = "plugin vcs -- log-preview"
desc = "Toggle VCS log preview"
```

The action splits the existing Preview area vertically into equal halves. The
upper half uses the normal Yazi preview for the hovered item; the lower half
shows up to five newest Git or SVN entries for that item. Moving the hover
updates the log automatically, and invoking the action again disables the
split. The existing `g v p` Push and `g v l` CLI Log bindings remain unchanged.

The custom previewer must also be registered by the user in `yazi.toml`:

```toml
[[plugin.prepend_previewers]]
url = "*"
run = "vcs"
```

Keep any more-specific previewer rules before this catch-all rule. The lower
pane reports repository, history, untracked-file, and command errors without
removing the upper preview. Restart Yazi after changing the configuration.
