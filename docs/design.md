# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 2。

## 構成

- `main.lua`: fetcher、先頭列描画、status refresh、entry dispatch
- `actions.lua`: Update／Commit／Diff／Log／Discardの非同期操作
- `core-runner.lua`: `Command:spawn()`による非対話実行、タイムアウト、`ui.hide()`による対話実行
- `core-targets.lua`: 対象選択、root境界、未追跡除外、確認文
- `core-commands.lua`: Git／SVNの安全な引数配列
- `core-state.lua`: root別statusと操作ロック
- `backend-git.lua`／`backend-svn.lua`: Status取得と解析

## 操作フロー

```text
selected -> hovered -> current
        │
        ▼
root検出 -> root相対化・境界検証 -> backend引数構築
        │
        ├─ Update/Commit/Discard -> runner -> 成功時state破棄 -> refresh
        └─ Diff/Log -> runner -> 一時出力ファイル -> pager/editor
```

CommitはGitの`paths`モードを既定とし、選択パスを`--`以降へ渡します。これにより
選択外のstage済み変更を巻き込みません。`staged`モードではパスを渡しません。
Discardでは未追跡・ignored状態を操作対象から除外し、ディレクトリは再帰確認を要求します。

## 検証境界

純粋Luaで設定マージ、パス境界、対象選択、引数配列、出力整形を検証します。実CLIの
Git／SVN Status結合テストは既存テストで継続します。実Yaziの`ui.hide()`、editor／pager、
Windows／WSL、SVNの未検証状態は手動確認が必要です。
