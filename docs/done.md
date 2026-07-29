# 完了記録

## 2026-07-29 — vcs.yazi Phase 3（Git拡張）実装

- `core-git.lua`: Push／Branch／Switchの引数構築、Branch一覧・remote解析、Branch名入力検証
- `git-actions.lua`: Push、upstream未設定時のremote選択、Branch一覧／作成／名称変更／安全削除、local／remote tracking Switch
- `core-state.lua`の操作ロックと成功後refreshをPhase3操作へ接続
- Pushは`ui.hide()`配下で認証入力を許容し、Force Push／Force Delete／自動stash／強制Switchを実行しない
- `config.lua`へ`git.push`／`git.branch`／`git.switch`設定を追加
- README、ユーザーマニュアル、設計書、TODOをPhase3へ更新
- Gitローカルbare repository結合テストを追加
- Lua 5.5テスト: 157 passed / 0 failed
