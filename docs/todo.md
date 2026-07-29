# TODO

未着手・未完了の作業一覧。完了したら [done.md](done.md) へ移すこと。

---

## バグ修正（`/code-review medium` 検出分、2026-07-29）

GitHub Issue化済み。詳細・再現手順・修正案は各Issue本文を参照。

- [ ] [#1](https://github.com/hironei/yazi_vcs/issues/1) — `excluded` ステータスが表示時に `ignored` へ変換されない（bug）
- [ ] [#2](https://github.com/hironei/yazi_vcs/issues/2) — `deep_merge` が明示的な `false` オーバーライドを無視する（bug）
- [ ] [#3](https://github.com/hironei/yazi_vcs/issues/3) — `is_within`/`strip_prefix` がドライブルート直下のVCSルートで二重スラッシュになる（bug）
- [ ] [#4](https://github.com/hironei/yazi_vcs/issues/4) — `status.aggregate_directories`/`status.ignore_externals` が未実装で設定しても効果がない（bug）
- [ ] [#5](https://github.com/hironei/yazi_vcs/issues/5) — backend `fetch()` の返り値の数がGit/SVNで揃っておらず `main.lua` に分岐が漏れている（enhancement）
- [ ] [#6](https://github.com/hironei/yazi_vcs/issues/6) — SVN `classify()` で `external` が `property_modified` より優先されうる（bug・未確定/PLAUSIBLE）

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
