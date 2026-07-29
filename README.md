# yazi_vcs

Yazi で Git と Subversion の作業状態をファイル一覧の先頭列へ表示する
`vcs.yazi` プラグインです。現在は Phase 1（Status MVP）で、リポジトリを
自動判定し、変更状態の取得・表示・手動更新を提供します。

## 現在の状態

実装済み:

- Git / SVN リポジトリの自動判定
- Git porcelain v2 と SVN `status --xml` の解析
- modified、added、deleted、renamed、untracked、ignored、conflict などの表示
- ディレクトリへの子孫状態の集約
- Git の ignored ディレクトリと SVN の property/lock 状態の表示
- Yazi fetcher による非同期取得と手動 refresh

未実装（Phase 2 以降）:

- Update、Commit、Diff、Log、Discard
- Git Push、Branch 操作、Switch
- 外部 diff / log ビューアと Windows GUI ツール連携

## 必要な環境

- Yazi 26.5.6 以降
- Git 2.30 以降（Git リポジトリを使う場合）
- SVN 1.9 以降（SVN 作業コピーを使う場合）
- Linux、macOS、Windows、または WSL

## インストール（ローカル開発版）

まだパッケージレジストリへ公開していないため、プラグインディレクトリを
Yazi の設定へコピーまたはリンクします。

```bash
# Linux / macOS / WSL
mkdir -p ~/.config/yazi/plugins
ln -s /path/to/yazi_vcs/vcs.yazi ~/.config/yazi/plugins/vcs.yazi
```

Windows の場合は `%APPDATA%\yazi\config\plugins\vcs.yazi` へ
`vcs.yazi` をコピーするか、ディレクトリジャンクションを作成します。

詳細な設定と使い方は [ユーザーマニュアル](docs/users-manual.md) を参照してください。

## 最小設定

`~/.config/yazi/yazi.toml` に fetcher を登録します。この設定がないと
プラグインは読み込まれても状態取得が実行されません。

```toml
[[plugin.prepend_fetchers]]
id    = "vcs"
url   = "*"
run   = "vcs"
group = "vcs"

[[plugin.prepend_fetchers]]
id    = "vcs"
url   = "*/"
run   = "vcs"
group = "vcs"
```

`~/.config/yazi/init.lua`:

```lua
require("vcs"):setup()
```

手動更新用に `~/.config/yazi/keymap.toml` へ追加します。

```toml
[[mgr.prepend_keymap]]
on   = [ "<C-g>", "s" ]
run  = "plugin vcs -- status"
desc = "Refresh VCS status"
```

## ドキュメント

- [ユーザーマニュアル](docs/users-manual.md)
- [as-built 設計書](docs/design.md)
- [要件定義](docs/requirements.md)
- [プラグイン README](vcs.yazi/README.md)
- [TODO](docs/todo.md) / [完了記録](docs/done.md)

## テスト

```bash
cd vcs.yazi
lua tests/run.lua
```

純粋 Lua の単体テストに加え、PATH に `git` / `svn` があれば一時リポジトリを
使った結合テストも実行します。結合テストは Windows と POSIX shell の両方に
対応しています。実 Yazi の描画、色、既存 `git.yazi` との同時利用は別途
目視確認が必要です。

## 制約と安全性

Phase 1 は status の読み取りと表示だけを行います。Commit、Discard、Push などの
破壊的操作はまだ提供していません。認証情報を取得・保存・通知する機能もありません。
SVN の external / obstructed / incomplete 状態と TUI 上の最終的な見た目は、
実作業コピーでの追加確認が必要です。

## ライセンス

MIT License（[vcs.yazi/LICENSE](vcs.yazi/LICENSE)）
