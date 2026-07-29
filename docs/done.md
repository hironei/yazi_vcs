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

## 2026-07-29 — vcs.yazi Phase 4（外部連携・改善）実装

- `core-external.lua`: 外部コマンド設定検証、プレースホルダー展開、WSL／Git Bash環境判定
- `actions.lua`: `diff --external`／`log --external`、TUIの占有実行、GUIの非占有起動、外部GUIパス変換
- `core-runner.lua`: GUI向け非待機`launch`を追加
- `config.lua`: `diff.*_external`、`log.*_external`、`path.external_style`を追加
- `main.lua`: fetcherへ重複パス抑止を追加し、表示中パスだけのstatus取得を維持
- `examples/svn-difft-wrapper.sh`: SVN固定引数を外部2ファイルDiffへ変換するラッパー例
- README、ユーザーマニュアル、設計書、TODOをPhase4へ更新
- 外部設定・環境判定・設定マージテストを追加
- Lua 5.5テスト: 172 passed / 0 failed
