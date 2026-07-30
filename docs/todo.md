# TODO

## バグ修正（レビュー検出分、2026-07-30）

- [x] [#11](https://github.com/hironei/yazi_vcs/issues/11) — `runner.timeout_ms = 0`が実際にはタイムアウトを無効化しない
- [x] [#12](https://github.com/hironei/yazi_vcs/issues/12) — Git push起動失敗時、実spawnエラーが「exit code unknown」に握りつぶされる
- [x] [#13](https://github.com/hironei/yazi_vcs/issues/13) — Discardのディレクトリ再帰判定がスナップショット不整合でfalseになり得る
- [x] [#14](https://github.com/hironei/yazi_vcs/issues/14) — core-runner.luaが読み取り専用のStatusオブジェクトへ書き込んでいる
- [x] [#15](https://github.com/hironei/yazi_vcs/issues/15) — stdout/stderrの行がseparatorなしで連結されている
- [x] [#16](https://github.com/hironei/yazi_vcs/issues/16) — `git.branch.allow_force_delete`／`validate_name`（安全要件に反するため実装せず設定キーを削除）
- [x] [#17](https://github.com/hironei/yazi_vcs/issues/17) — `git.switch.auto_stash`／`allow_discard_changes`（同上、削除）
- [x] [#18](https://github.com/hironei/yazi_vcs/issues/18) — `git.push.allow_force`（同上、削除）
- [x] [#19](https://github.com/hironei/yazi_vcs/issues/19) — `discard.include_untracked`（同上、削除）
- [x] [#20](https://github.com/hironei/yazi_vcs/issues/20) — `commit.default_scope`／`editor.wait`（未実装機能のため設定キーを削除）

## 目視確認（ユーザー対応が必要）

- [ ] 実際のYazi画面でPhase2〜4のキー操作と通知を確認する
- [ ] Git認証が必要なPushをWindows 11のGit Bash／WSLで確認する
- [ ] Git Branch入力UIとpager表示を実Yaziで確認する
- [ ] 外部Diff／LogのTUIとWindows GUI起動を実環境で確認する
- [ ] `git.yazi`との同時利用で記号が二重表示されないか確認する
- [x] WSLの`wslpath -w`、Git Bashの`cygpath -w`によるGUIパス変換を確認する

## Phase 4：外部連携・改善

- [x] 外部Diff（`--diff-cmd`ラッパーを含む）
- [x] 外部Log
- [x] Windows GUIツール連携
- [x] WSL／Git Bashパス変換経路
- [x] 大規模リポジトリ向けstatus範囲・index lock配慮
- [x] 外部設定・環境判定テスト拡充

## 未検証事項

- [x] SVNの`external`／`obstructed`／`incomplete`状態を実作業コピーで再現する
- [x] SVN update／commit／revertのWindows実CLI確認
- [ ] 外部GUIの実起動と終了待ちなし動作
