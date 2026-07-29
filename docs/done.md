# 完了記録

日付降順ではなく、実施順（古い→新しい）で記録する。

---

## 2026-07-29 — 要件定義の検証・修正

- ユーザー提供の `yazi-vcs-plugin-requirements.md` を、Yazi 26.5.6 の実ソース（`yazi-runner`/`yazi-plugin`）・公式 `git.yazi` プラグイン・Git CLI の実測結果と突き合わせて検証
- 実装不可能だった3点を修正: モジュール構成（サブディレクトリ不可→フラット構成）、ステータス取得契機（独自キャッシュ→Yaziのfetcher機構）、Git Commitの暗黙stage挙動
- `--ignored=matching`、rename時のNULフィールド、`v`キー衝突、タイムアウト実現方式、外部diffのラッパー必須化などを追加・修正
- `docs/requirements.md` として保存
- コミット: `a7ecc56`

## 2026-07-29 — vcs.yazi Phase 1（Status MVP）実装

- SVN CLI（TortoiseSVN由来、1.14.5）・Lua 5.5（mluaの`lua55`featureに合わせてscoopでインストール）を実行環境に追加
- Yaziの `require()` 制約（kebab-case・フラット構成のみ）を実ソースで確認したうえでモジュール設計を確定
- 以下を実装（`vcs.yazi/`）:
  - `core-path.lua` / `core-status.lua` / `core-detector.lua` の純粋ロジック（素のluaで単体テスト可能）
  - `core-state.lua`（`ya.sync`永続ストレージ）、`core-notify.lua`
  - `backend-git.lua`（porcelain v2 -z 解析、rename NULフィールド対応）
  - `backend-svn.lua`（`svn status --xml` 解析。実測により判明したSVN固有仕様に対応: パスをそのまま返す、`<lock>`は要素、`--`終端必須）
  - `main.lua`（fetcher登録、`Entity:children_add`による先頭列表示、手動refresh）
  - `config.lua`、`README.md`、`LICENSE`
- テスト: `tests/run.lua` で88件（純粋ロジック単体テスト＋実git/svnバイナリを使った結合テスト）が全件成功
- 実Yazi環境（`%APPDATA%\yazi\config`）へジャンクション接続し、`yazi.toml`/`init.lua`/`keymap.toml`を設定。一時的な`ya.dbg`計装により、Gitリポジトリ・SVN作業コピー・非VCSディレクトリの3パターンで`fetch()`が実際にエラーなく完走することを確認（確認後に計装は削除）
- コミット: `a6d2e4e`（ユーザー承認により作成、push未実施の状態）

## 2026-07-29 — コードレビュー（`/code-review medium`）実施

- 8つの観点（正確性3・再利用・簡略化・効率・altitude・CLAUDE.md準拠）で並列調査、候補を収集
- 候補を検証パスにかけ、7件中: CONFIRMED 5件、PLAUSIBLE 1件、REFUTED 1件（fetch失敗時の通知欠如——公式git.yazi参照実装と同一挙動と判明し却下）、加えて「capabilities未使用」は意図的な先行実装と判定し除外
- 最終的に6件をReportFindingsで報告

## 2026-07-29 — レビュー結果をGitHub Issue化・push

- リモート（`github.com/hironei/yazi_vcs`、public、単独オーナー）が空だったことを確認
- レビュー指摘6件をIssue #1〜#6として登録（各Issueに再現コード・失敗シナリオ・修正案を記載）
- ユーザーの明示的な許可を得て `git push -u origin main` を実行し、`a7ecc56`・`a6d2e4e` をリモートへ反映

## 2026-07-29 — 設計書・作業記録の整備

- `docs/design.md` を作成: as-built設計（モジュール構成、レイヤリング方針、データフロー、`ya.sync`の挙動、実装時に判明した仕様上の発見4件、バックエンド抽象化の歪み、状態優先度、テスト戦略、既知の制約）
- `docs/todo.md` / `docs/done.md` を作成し、作業記録を分離

## 2026-07-29 — GitHub Issue #1〜#6 修正

- Issue #1: 内部 excluded を表示時の ignored へ変換
- Issue #2: deep_merge で明示的な false 設定を保持
- Issue #3: POSIXルートおよびドライブルート直下のパス境界を修正
- Issue #4: aggregate_directories と ignore_externals を実際のfetch経路へ接続
- Issue #5: Git/SVN backendの fetch() 返り値を (changed, excluded, err) へ統一
- Issue #6: SVNの property_modified を external より優先
- 各Issueの再発条件を純粋Luaテストへ追加

## 2026-07-29 — GitHub Issue #7 修正

- ディレクトリ状態集約を `job.files[1]` の種別に依存させず、設定有効時は全fetch結果へ適用
- 混在一覧で先頭がファイルでも配下の変更を親ディレクトリへ集約できるよう修正
