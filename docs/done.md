# 完了記録

## 2026-07-29 — Issue #9/#10整理

- Issue #9: Windowsパスの単一バックスラッシュをfile URLへ変換する回帰を修正
- Issue #10: Issue #8後に不要となった`core-state.current_cwd`を削除
- 回帰テストをテスト補助へ追加

## 2026-07-29 — vcs.yazi Phase 2（共通操作）実装

- `core-runner.lua`: 引数配列による外部コマンド実行、標準出力／標準エラー、終了コード、タイムアウト、`ui.hide()`による対話実行
- `core-targets.lua`: selected → hovered → currentの対象決定、root境界検証、未追跡・ignored対象のDiscard除外
- `core-commands.lua`: Git／SVNのUpdate、Commit、CLI Diff、CLI Log、Discard引数構築
- `actions.lua`: Update、Commit（エディタ・UTF-8一時ファイル・stage挙動確認）、pager表示のDiff／Log、確認付きDiscard、実行後refresh
- `core-state.lua`: 操作中の同一root競合抑止
- 設定へeditor／pager／update／commit／discard／runnerを追加
- 純粋Luaの対象選択・引数・runner補助テストを追加
