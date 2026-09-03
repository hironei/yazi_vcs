# 完了記録

## 2026-09-03 — Temporary VCS Log Spot (Issue #47)

- Added `plugin vcs -- log-spot`, which uses Yazi's dynamic Spotter API for a
  one-shot selectable Git/SVN history table with up to five entries.
- Removed the temporary Spotter before querying or rendering and kept the
  standard Spotter list untouched for later Spot actions.
- Added the optional `[spot]` Tab bridge so VCS Log Spot switches to the normal
  Spot while standard Spot Tab retains its close behavior.
- Reused log-preview command, parser, timeout, and error handling and added
  table-row unit coverage. Live Yazi 26.8.15 UI acceptance remains required.

## 2026-08-31 — Hovered-File VCS Log Preview Pane (Superseded)

- Added the opt-in `plugin vcs -- log-preview` action and documented `g v v` without changing the existing Push (`g v p`) or CLI Log (`g v l`) bindings.
- Split the existing Yazi Preview area vertically into equal normal-preview and log areas, refreshing the hovered item's Git/SVN history with at most five one-line entries.
- Added pure command/parser/message helpers, per-tab toggle state, standard Yazi preview delegation, Git/SVN integration coverage, and English setup documentation including the required `yazi.toml` previewer rule.
- Native Windows Lua tests passed: 341 passed / 0 failed; `luac -p` passed. A temporary Yazi 26.8.15 configuration launched successfully and the toggle action completed without Lua errors; full visual Git/SVN/hover-movement acceptance remains a manual follow-up.

## 2026-09-01 — Temporary VCS Log Notification

- Replaced the Preview-area split with an eight-second multi-line notification showing the current item's latest five Git/SVN entries.
- Removed per-tab toggle and hover-refresh behavior so standard Preview and split-tabs layouts remain untouched.
- Kept a compatibility pass-through for stale custom `run = "vcs"` previewer rules and added notification formatting coverage.
- Native Windows Lua tests passed: 340 passed / 0 failed; `luac -p` and `git diff --check` passed. Live notification rendering was not completed because the temporary Yazi configuration directory was blocked by local ACLs.

## 2026-08-31 — VCS Changes View (Issue #42)

- Added `plugin vcs -- changes`, backed by a repository-wide Git/SVN status query and Yazi's native Search View.
- Reused the existing backend parsers, included untracked paths, omitted clean/ignored paths, and retained deleted paths with synthetic metadata.
- Normalized Search URLs to physical paths and made Search View Diff, Log, Add, Commit, and Discard selection-only; Git untracked Diff uses `--no-index`, and untracked Log entries are reported and skipped.
- Added unit and Git integration coverage. Native Windows Lua tests passed; real Yazi UI and Windows/Git Bash manual checks remain pending.

## 2026-08-20 — VCS操作のselected／cwd scope統一（Issue #36）

- VCS操作開始時のselected／cwd／file metadata snapshotと、`selected > cwd`の共通scope／repository resolverを追加
- hoveredを操作対象から除外し、selected pathからのVCS root解決、複数repository／Git-SVN／VCS外混在の拒否、repository rootのDiff／Log scopeを実装
- cwd scopeのAdd／Commit／Discardに対象範囲を明示するtyped confirmationを追加し、既存のforce操作禁止・未追跡削除禁止を維持
- requirements、design、README、users manual、TODOを現行仕様へ更新。純粋Luaテストは179 passed、全体統合テストはWindows Luaの一時ディレクトリ環境要因で未完了

## 2026-08-11 — Review findings #25〜#30 修正

- `config.lua`: マップは深いマージ、配列は指定値で全体置換する設定マージへ修正。空配列と短いコマンド配列の回帰テストを追加
- `actions.lua`: Updateを`ui.hide()`下の対話経路へ変更し、認証入力を許可。status／Diff／Log／revisionのread-only CLIをtimeout付きRunnerへ統一
- `main.lua`／`git-actions.lua`: fetcherのstatus/info、Branch検証・一覧もtimeout付きRunnerへ統一
- `core-runner.lua`／操作dispatch: 対話permitとroot操作ロックをLua例外時にも解放する`pcall`保護を追加
- `docs/requirements.md`／`docs/design.md`／README／`docs/users-manual.md`: 現行仕様、timeout境界、認証、設定マージ、要件・設計トレーサビリティを同期
- WindowsネイティブLua: `lua tests/run.lua`（204 passed / 0 failed）
- Issue: [#25](https://github.com/hironei/yazi_vcs/issues/25)、[#26](https://github.com/hironei/yazi_vcs/issues/26)、[#27](https://github.com/hironei/yazi_vcs/issues/27)、[#28](https://github.com/hironei/yazi_vcs/issues/28)、[#29](https://github.com/hironei/yazi_vcs/issues/29)、[#30](https://github.com/hironei/yazi_vcs/issues/30)

## 2026-08-05 — status barのVCS位置表示

- status bar右側へGitの現在branch（`(branch-name)`）を表示
- SVNはfetcherで取得したworking-copy URLへ対象のroot-relative pathを付加し、`(svn: https://host/svn/base_url/trunk/file.txt)`のように表示
- 描画中のCLI実行を避け、fetcherで取得したroot別stateを参照
- Git／SVN URL解析と表示整形の単体テストを追加

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

## 2026-07-30 — `/code-review`実施（Phase 3/4対応コミット群）

- 8観点の並列調査を経て、上位10件を報告
- `timeout_ms=0`が無効化されない、Git push起動失敗時のエラー握りつぶし、Discard再帰判定のスナップショット不整合、core-runner.luaの読み取り専用Status書き込み・改行なし連結の5件はコード直接確認済み
- `config.lua`で宣言されているが未使用の設定キー5件（`branch.allow_force_delete`／`validate_name`、`switch.auto_stash`／`allow_discard_changes`、`push.allow_force`、`discard.include_untracked`、`commit.default_scope`／`editor.wait`）をgrepで確認
- Issue #11〜#20として起票

## 2026-07-30 — GitHub Issue #11〜#20 修正

- #11: `core-runner.lua`に純粋関数`next_poll()`を切り出し、`timeout_ms=0`（無効）時にevent=3を実タイムアウトとして扱わないよう修正。単体テスト追加
- #12: `git-actions.lua`のPush失敗処理を、他の`fail()`呼び出し箇所と同じ`status and {...} or nil`パターンに統一し、spawn失敗時の実エラーを保持するよう修正
- #13: `actions.lua`のDiscardが、`info`と`absolute`を`selected_targets()`内の単一の`current_context()`呼び出しから取得するよう統一。`Path.join_native`によるキー再構築をやめ、`view_operation()`と同じ構成に揃えた
- #14/#15: `core-runner.lua`が`child:wait()`の返すStatusオブジェクトへ書き込むのをやめ、タイムアウト時は別テーブルへ差し替え。`table.concat`にseparator（`"\n"`）を明示
- #16〜#19: `docs/requirements.md` §25「安全要件」（Force Delete／Force Push／自動stash／未追跡ファイル自動削除の禁止）を確認した結果、該当4件の設定キーは実装すると安全要件に違反すると判明。ユーザー確認のうえ実装せずconfig.luaから削除
- #20: `commit.default_scope`／`editor.wait`は現行アーキテクチャでは効果を持たせられない未実装機能と判明。ユーザー確認のうえconfig.luaから削除
- 各修正を個別コミット・Issueコメント・クローズ。WindowsネイティブLuaでは`lua tests/run.lua`（180 passed / 0 failed、SVN統合含む）を確認。WSLではSVN CLIのパス形式差により統合をスキップし、178 passed / 0 failed

## 2026-07-30 — Windows／WSL／SVN実環境確認

- WindowsネイティブLuaの全テスト（SVN統合を含む）: 180 passed / 0 failed
- Windows SVN 1.14.5で`external`／`obstructed`／中断checkoutによる`incomplete`を再現し、status XMLと分類結果を確認
- Windows SVN 1.14.5でupdate／commit／revertを確認
- WSLの`wslpath -w`とGit Bashの`cygpath -w`で空白を含むパスの変換を確認
- Git Bashのローカルbare repositoryへのPushを確認（認証付きリモートは未実施）
