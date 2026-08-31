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

## バグ修正（レビュー検出分、2026-08-11）

- [x] [#25](https://github.com/hironei/yazi_vcs/issues/25) — 配列型設定の再帰マージで既定引数が混入する
- [x] [#26](https://github.com/hironei/yazi_vcs/issues/26) — Updateが認証入力を受け付けない
- [x] [#27](https://github.com/hironei/yazi_vcs/issues/27) — status／Diff／Log／メタデータ取得がtimeoutを迂回する
- [x] [#28](https://github.com/hironei/yazi_vcs/issues/28) — Lua例外時に操作ロック／terminal permitが残る
- [x] [#29](https://github.com/hironei/yazi_vcs/issues/29) — 要件書が削除済み設定と現行動作を記載している
- [x] [#30](https://github.com/hironei/yazi_vcs/issues/30) — as-built設計書が現行実装と一致しない

## バグ修正（レビュー検出分、2026-08-18）

- [x] [#34](https://github.com/hironei/yazi_vcs/issues/34) — Commitの`ya.confirm()`がWindows上のfunctional plugin taskで描画されずタスクが保留状態になる（#22と同種）。Commit・Git Branch削除の確認を`ya.input()`によるタイプ確認へ統一
- [x] [#36](https://github.com/hironei/yazi_vcs/issues/36) — VCS操作対象を`selected > cwd`へ統一し、repository境界検証とcwd scopeのRisk Policyを導入する

## 対応中（2026-08-23）

- [ ] [#38](https://github.com/hironei/yazi_vcs/issues/38) — Yazi 26.8.15対応: fetcher API更新とYazi依存の互換レイヤ分離（`core-fetcher.lua`新設、`main.lua`のfetcher契約更新、`core-context.lua`のFile／Url対応、対応Yaziバージョンを26.8.15以降へ更新。自動テストは通過済みだが、下記「目視確認」のWindows + Yazi 26.8.15実機確認が未了のためissueは未クローズ）
- [ ] [#42](https://github.com/hironei/yazi_vcs/issues/42) — VCS Changes View（Git/SVN変更一覧、Search View選択、Diff／Log／Add／Commit／Discard連携）を実装。自動テスト済み、実Yazi UIとWindows/Git Bashの手動確認待ち。

## 目視確認（ユーザー対応が必要）

- [x] 実際のYazi画面でPhase2〜4のキー操作と通知を確認する
- [x] Windows実Yazi上で`g v c`（Commit）と`g v b` → deleteの確認ダイアログ・タスク終了を確認する（#34の修正確認）
- [ ] Git認証が必要なPushをWindows 11のGit Bash／WSLで確認する
- [ ] Git Branch入力UIとpager表示を実Yaziで確認する
- [x] 外部Diff／LogのTUIとWindows GUI起動を実環境で確認する
- [ ] `git.yazi`との同時利用で記号が二重表示されないか確認する
- [x] WSLの`wslpath -w`、Git Bashの`cygpath -w`によるGUIパス変換を確認する
- [x] （#38、要件§26.5）Windows + Yazi 26.8.15でGitリポジトリを開いてもfetcher Taskが残り続けない
- [x] （#38）Git status記号が表示される
- [ ] （#38）ファイル編集後にstatusが更新される
- [ ] （#38）`git add`／`git commit`後にstatusが更新される
- [ ] （#38）VCS外ディレクトリでもTaskが残留しない
- [ ] （#38）選択あり／なし双方で既存VCS操作が動作する
- [ ] （#38）SVN環境でもstatus fetcherがTaskを残留させない
- [ ] （#38）正常時に毎回`{retry=true}`を返す方式でも、CLIプロセス再起動やCPU使用率が実用上問題ない範囲に収まっている

## Phase 4：外部連携・改善

- [x] status barへGit branch／SVNのリポジトリ相対位置を表示
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
