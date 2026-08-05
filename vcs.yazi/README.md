# vcs.yazi

Git／SVNの状態とリポジトリ位置表示、Phase 2の共通操作、Phase 3のGit操作、Phase 4の外部Diff／Log連携を提供するYaziプラグインです。status bar右側にGitの現在branch、またはSVNの`base_url/trunk`のようなリポジトリ相対位置を表示します。

Phase 4の操作:

- CLI Diff／Log: `plugin vcs -- diff`、`plugin vcs -- log`
- 外部Diff／Log: `plugin vcs -- diff --external`、`plugin vcs -- log --external`
- TUIは`interactive = true`で`ui.hide()`配下、GUIは`interactive = false`で非占有起動
- WSLの`wslpath -w`、Git Bashの`cygpath -w`による外部GUIパス変換

外部コマンドは`diff.git_external`／`diff.svn_external`／`log.git_external`／`log.svn_external`へ、`command`と`args`を配列で設定します。`{root}`、`{file}`、`{targets}`、`{revision}`を使用できます。`{targets}`は対象ごとに別引数へ展開されます。

SVNの`--diff-cmd`へdifftastic等を接続する例は[`../examples/svn-difft-wrapper.sh`](../examples/svn-difft-wrapper.sh)を参照してください。

既存のPush・Branch・Switchの安全方針、CLI操作の失敗通知、成功後refreshも維持します。実Yazi UI、Windows GUI、WSL／Git Bash、SVN実CLIは手動確認が必要です。
