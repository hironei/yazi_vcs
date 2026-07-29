# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 3。

## 構成

- `main.lua`: fetcher、状態表示、status refresh、操作dispatch
- `actions.lua`: Phase 2の共通操作
- `git-actions.lua`: Push、Branch、SwitchのYazi操作フロー
- `core-git.lua`: Gitの引数構築、Branch／remote出力解析、Branch名入力検証
- `core-runner.lua`: 非対話runner、タイムアウト、`ui.hide()`による対話実行
- `core-state.lua`: root別statusと同一root操作ロック

## Git操作フロー

```text
Git root検出 -> 操作ロック -> CLI前提確認
      │
      ├─ Push: current branch -> upstream -> remote選択 -> ui.hide + git push
      ├─ Branch: list/入力 -> branch名検証 -> branch/confirm -> state破棄 + refresh
      └─ Switch: local/remote判定 -> switch/--track -> state破棄 + refresh
```

Pushはupstreamがあれば`git push`、なければremoteと現在Branchを明示して
`git push --set-upstream <remote> <branch>`を実行します。Force系引数は構築しません。

Branch削除は`git branch -d`のみを使用し、現在Branchとremote Branchを拒否します。
Switchはremote tracking Branchがローカルにない場合のみ`git switch --track`を使い、
自動stashや`--discard-changes`は実装しません。

## 検証境界

純粋LuaテストでGit引数・Branch名検証・Branch出力解析を確認し、ローカルbare repositoryで
Push、upstream、Branch作成／名称変更／安全削除、remote tracking Switch、detached HEADを
結合検証します。実Yazi UI・認証入力・SVN CLI・Windows／WSLは手動確認が必要です。
