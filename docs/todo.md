# TODO

未着手・未完了の作業一覧。完了したら [done.md](done.md) へ移すこと。

---

## バグ修正（レビュー検出分、2026-07-29）

- [x] [#7](https://github.com/hironei/yazi_vcs/issues/7) — 混在一覧で先頭がファイルの場合、ディレクトリ配下の変更が集約表示されない
- [x] [#8](https://github.com/hironei/yazi_vcs/issues/8) — 初回fetch完了前の手動Status更新が、未保存のrootを非VCSとして扱う
- [ ] [#9](https://github.com/hironei/yazi_vcs/issues/9) — （再オープン）修正コミット `1a28714` の `to_file_url()` がWindowsで単一バックスラッシュを変換できず、SVN結合テストが `svn checkout` で失敗する回帰
- [ ] [#10](https://github.com/hironei/yazi_vcs/issues/10) — Issue #8 修正後、`core-state.current_cwd` が未使用のまま残存

## 目視確認（ユーザー対応が必要）

- [ ] 実際のYazi画面で状態記号の色・位置を確認する（TUIのため自動化不可）。動作確認用に `%APPDATA%\yazi\config` へ `vcs.yazi` をジャンクション接続済み、`yazi.toml`/`init.lua`/`keymap.toml` に設定追加済み
- [ ] 既存の `git.yazi`（package.toml管理）と `vcs.yazi` が両方有効な状態になっている。Gitリポジトリで記号が二重表示されないか確認し、必要なら `git.yazi` 側のfetcher登録を無効化する

## Phase 2：共通操作（requirements.md §29）

- [ ] 外部コマンド実行基盤（タイムアウト含む、§21）
- [ ] ターミナル占有機構（`ui.hide()`、§21.2）
- [ ] Update（`git pull --ff-only` / `svn update`、§10）
- [ ] Commit（任意エディタ・一時ファイル、§11）
- [ ] CLI Diff（任意pager、§12）
- [ ] CLI Log（§13）
- [ ] Discard changes（確認UX、§14）
- [ ] 複数ファイル対応の結合テスト

## Phase 3：Git拡張（requirements.md §29）

- [ ] Git Push（§15）
- [ ] Branch一覧／作成／名称変更／安全削除（§16）
- [ ] Git Switch（§17）
- [ ] リモート追跡Branch対応

## Phase 4：外部連携・改善（requirements.md §29）

- [ ] 外部Diff（Beyond Compare `bcomp.exe` を含むラッパースクリプト同梱、§12.5）
- [ ] 外部Log
- [ ] Windows GUIツール連携
- [ ] WSLパス変換
- [ ] 大規模リポジトリ性能改善
- [ ] テスト拡充

## 未検証事項（requirements.md §26.4 由来、継続）

- [ ] SVNの `external` / `obstructed` / `incomplete` 状態を実際の作業コピーで再現・検証する（Issue #6とも関連）
