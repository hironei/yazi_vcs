# vcs.yazi

Git／SVNの状態表示、Phase 2の共通操作、Phase 3のGit操作を提供するYaziプラグインです。

Phase 3の操作:

- Git Push: `plugin vcs -- push`
- Branch一覧／作成／作成後Switch／名称変更／安全削除: `plugin vcs -- branch`
- Git Switch（ローカル／remote tracking）: `plugin vcs -- switch`

Pushはupstreamを確認し、未設定時はremoteを選んで`--set-upstream`を使います。
認証入力の可能性があるため、Pushは`ui.hide()`配下の継承端末で実行します。

Branch名はCLI実行前に検証し、削除は`git branch -d`固定です。現在Branch・remote Branch・
Force Deleteは対象外です。Switchは自動stash／強制破棄を行わず、CLI失敗を通知します。

未実装: 外部Diff／Log、Windows GUI連携、WSLパス変換。
