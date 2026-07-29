# vcs.yazi ユーザーマニュアル

## 1. このプラグインについて

`vcs.yazi` は、Yazi のファイル一覧に Git / SVN の状態記号を表示します。
現在は Status MVP であり、状態取得・表示・手動 refresh が対象です。
Commit や Push などの操作クライアントではありません。

対応バージョンは Yazi 26.5.6 以降です。Git または SVN は、使用する種類の
リポジトリに対して PATH へ登録してください。

## 2. インストール

### Linux / macOS / WSL

```bash
mkdir -p ~/.config/yazi/plugins
ln -s /path/to/yazi_vcs/vcs.yazi ~/.config/yazi/plugins/vcs.yazi
```

既に同名ディレクトリがある場合は、古いリンクやコピーを整理してから配置します。
WSL で Snap 版 Yazi を使う場合も、Yazi が参照する Linux 側の
`~/.config/yazi/plugins` を使用します。

### Windows

`%APPDATA%\yazi\config\plugins\vcs.yazi` に `vcs.yazi` をコピーするか、
PowerShell でディレクトリジャンクションを作成します。

```powershell
New-Item -ItemType Junction `
  -Path "$env:APPDATA\yazi\config\plugins\vcs.yazi" `
  -Target "C:\path\to\yazi_vcs\vcs.yazi"
```

## 3. Yazi の設定

### 3.1 Fetcher（必須）

`~/.config/yazi/yazi.toml` に次を追加します。

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

`id` は新しい Yazi では省略できますが、26.5.6 との互換性を優先する場合は
残してください。fetcher 登録がない場合、`setup()` が成功しても状態は取得されません。

### 3.2 初期化

`~/.config/yazi/init.lua` に追加します。

```lua
require("vcs"):setup()
```

### 3.3 手動 refresh

`~/.config/yazi/keymap.toml` に追加します。既定の `v` は Yazi の
`visual_mode` と衝突するため使用しません。

```toml
[[mgr.prepend_keymap]]
on   = [ "<C-g>", "s" ]
run  = "plugin vcs -- status"
desc = "Refresh VCS status"
```

## 4. 使い方

1. Git リポジトリまたは SVN 作業コピーの配下へ移動します。
2. 一覧の左端に状態記号が表示されることを確認します。
3. 状態が変わったときは `<C-g>`、`s` で現在のルートを再取得します。

プラグインは表示中のファイルを対象に非同期で status を取得します。リポジトリ全体を
常に走査する設計ではありません。初回取得前に refresh しても、現在位置から VCS ルートを
再検出して更新を要求します。

## 5. 状態記号

| 状態 | 記号 | 説明 |
|---|---:|---|
| Conflict | `C` | Git unmerged、SVN conflicted / tree conflict |
| Missing | `!` | SVN で管理対象ファイルが作業コピーから消えた状態 |
| Deleted | `D` | 削除予定。Git の worktree deletion を含む |
| Replaced / Renamed | `R` | 置換または Git rename |
| Modified | `M` | 内容が変更された状態 |
| Property modified | `P` | SVN のプロパティだけが変更された状態 |
| Added | `A` | 追加済みまたは追加予定 |
| Untracked | `?` | VCS がまだ管理していないファイル |
| Locked | `L` | SVN のロックを検出した状態 |
| External | `X` | SVN external。実作業コピーでの確認は継続中 |
| Ignored | `I` | ignore ルールで除外された状態 |

ディレクトリには配下の状態を優先度に従って集約します。Conflict、Missing / Deleted、
Modified / Replaced、Added / Untracked、Locked / External、Ignored の順に強い状態が表示されます。

## 6. 設定

設定値は `setup()` に渡します。

```lua
require("vcs"):setup({
  signs = {
    conflict = "!",
    ignored = "·",
  },
  status = {
    order = 500,
    aggregate_directories = true,
    ignore_externals = true,
  },
  detection = {
    priority = { "git", "svn" },
  },
})
```

- `status.aggregate_directories`: `false` にすると子孫状態を親ディレクトリへ集約しません。
- `status.ignore_externals`: SVN の external を status 取得から除外します。既定は `true` です。
- `status.order`: 状態記号の表示順です。既定の `500` は Yazi の padding より前です。
- `detection.priority`: 同じ場所に Git と SVN のルートがある場合の優先順位です。

### テーマの色

Yazi のテーマで `th.vcs.<status>` を設定すると、状態記号の色を上書きできます。
記号自体は `signs` で変更します。ホバー中の行は背景との衝突を避けるため、記号を無装飾で表示します。

## 7. Git と SVN の違い

- Git は Missing を Deleted と区別しません。
- SVN は property-only modification と lock を報告できます。
- Git の ignored ディレクトリは `--ignored=matching` で検出します。
- SVN status は既定で `--ignore-externals` を付けます。必要なら `false` に変更してください。
- 同じディレクトリに両方のメタデータがある場合は、設定した priority とルートの近さで判定します。

## 8. トラブルシュート

### 状態記号が何も表示されない

次を確認します。

- `vcs.yazi` が Yazi の `plugins` ディレクトリにあるか。
- `yazi.toml` に `url = "*"` と `url = "*/"` の fetcher があるか。
- `init.lua` で `require("vcs"):setup()` を呼んでいるか。
- Git / SVN CLI が `PATH` にあるか。
- `<C-g>`, `s` で手動更新してみたか。

### Git リポジトリで二重に記号が出る

公式 `git.yazi` など別の status fetcher が同時に有効になっている可能性があります。
どちらか一方の fetcher を無効にしてから再確認してください。

### 「Not inside a Git or SVN working copy」と表示される

現在位置から親方向に `.git` または `.svn` が見える必要があります。Git worktree の
`.git` ファイルにも対応しています。サブディレクトリへ移動してから手動 refresh してください。

### WSL で Windows 側のリポジトリを開く

Yazi、Git/SVN CLI、プラグインを同じ環境で実行することを推奨します。WSL と Windows の
CLI を混在させる場合、パス表現・実行権限・改行コードの差により status が取得できないことがあります。

## 9. テストと既知の制約

```bash
cd /path/to/yazi_vcs/vcs.yazi
lua tests/run.lua
```

純粋 Lua の単体テストと、PATH にある Git/SVN を使う結合テストを実行します。Phase 1 では
Commit、Discard、Push、Branch、Switch、外部 diff/log は提供しません。SVN external / obstructed /
incomplete の実働確認と TUI の色・位置確認は別途必要です。

## 10. 関連資料

- [プロジェクト README](../README.md)
- [設計書](design.md)
- [要件定義](requirements.md)
- [TODO](todo.md)
