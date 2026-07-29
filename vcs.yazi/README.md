# vcs.yazi

Git／SVNの状態表示とPhase 2の共通操作を提供するYaziプラグインです。
ルートの[README](../README.md)と[要件定義](../docs/requirements.md)を参照してください。

実装済みの操作:

- Status refresh: `plugin vcs -- status`
- Update: `plugin vcs -- update`
- Commit: `plugin vcs -- commit`
- CLI Diff: `plugin vcs -- diff`
- CLI Log: `plugin vcs -- log`
- Discard changes: `plugin vcs -- discard`

操作は引数配列でCLIへ渡し、root外のパスを拒否します。Commitはエディタで一時
メッセージファイルを編集し、Discardは確認後に実行します。CLIの出力はpagerまたは
設定したeditorで表示します。

未実装: Git Push、Branch、Switch、外部Diff／Log、Windows GUI連携。
