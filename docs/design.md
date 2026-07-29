# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 1（Status MVP）実装。

この文書は、実装済みの構造・状態の流れ・テスト境界を記録します。実装していない
Phase 2 以降の操作は、要件定義とユーザーマニュアルで区別して記載します。

## 1. モジュール構成

Yazi のプラグインローダーは `plugins/{plugin}.yazi/{entry}.lua` を解決し、エントリ名に
kebab-case とフラット構成を要求します。そのため、論理的な層はファイル名の接頭辞で表現します。

```text
vcs.yazi/
├── main.lua             -- setup / fetch / entry / 先頭列描画
├── config.lua           -- 既定値と再帰マージ
├── core-detector.lua    -- Git/SVN ルート検出
├── core-path.lua        -- パス正規化とルート境界
├── core-status.lua      -- 優先度、集約、ignored bookkeeping
├── core-state.lua       -- ya.sync を使う状態ストレージ
├── core-notify.lua      -- 通知整形
├── backend-git.lua      -- Git status 引数、解析、Command 実行
├── backend-svn.lua      -- SVN status 引数、XML 解析、Command 実行
└── tests/               -- 素の Lua で実行する単体・結合テスト
```

`init.lua` はプラグインに含めません。ユーザーの `~/.config/yazi/init.lua` から
`require("vcs"):setup()` を呼び出します。

## 2. レイヤリング

| 層 | 主なファイル | 責務 | テスト境界 |
|---|---|---|---|
| 純粋ロジック | `core-path.lua`, `core-status.lua`, パーサ部分 | パス、状態優先度、集約、Git/SVN出力解析 | 素の Lua で単体テスト |
| Yazi アダプタ | `core-detector.lua`, backend の `fetch` | `fs`、`Url`、`Command` への接続 | 実 Yazi または実CLI |
| 状態層 | `core-state.lua` | `ya.sync` 越しの設定・root・status の共有 | 実 Yazi のスモーク確認 |
| 描画・入口 | `main.lua`, `core-notify.lua` | fetcher、手動 action、先頭列、通知 | 実 Yazi の目視・スモーク確認 |

描画コールバックでは I/O を行わず、`core-state.lua` に保存済みの状態だけを参照します。
CLI 実行と解析は非同期 fetcher 経路で行います。

## 3. データフロー

```text
Yazi fetcher (url="*" / url="*/")
        │ job.files
        ▼
main.lua:fetch
        │ cwd = first file's base/parent
        ▼
core-detector:detect
        │ 親方向へ .git / .svn を探索
        ▼
root-relative paths
        │ Path.strip_prefix（forward slash）
        ▼
backend-git / backend-svn:fetch
        │ Command(...):cwd(root):arg(...):output()
        ▼
parse → bubble_up / propagate_down → clean backfill
        ▼
core-state:remember（ya.sync）→ ui.render()
        ▼
Entity:children_add が先頭列へ状態記号を描画
```

### 3.1 Fetch の対象

`job.files` に渡された表示中のパスだけを root 相対へ変換し、status コマンドへ引数として渡します。
パスを shell 文字列へ連結せず、Yazi `Command:arg()` の引数配列を使います。出力に現れなかった
問い合わせ対象は `clean` として backfill し、前回の stale 状態を消します。

### 3.2 ディレクトリ集約

`status.aggregate_directories` が有効なら、fetch 結果のファイル状態を `bubble_up()` で全ての
祖先ディレクトリへ伝播します。ファイルとディレクトリが混在する一覧でも、先頭要素の種別には
依存しません。Git の完全 ignored ディレクトリは `propagate_down()` で表示対象または内部 sentinel
として扱い、ignored ファイルは親の状態へ伝播させません。

### 3.3 手動 refresh

`plugin vcs -- status` は `core-state.current_url()` で現在の Url を取得し、`Detector.detect()`
で root を再検出します。初回 fetch 前で state に root が保存されていない場合でも、検出した root を
クリアして `ya.emit("refresh", {})` を発行できます。

## 4. 状態ストレージ

`core-state.lua` の `ya.sync` 関数群が同一モジュールの状態テーブルを共有します。

```lua
state.config = merged_config
state.dirs  = { [cwd_string] = root_string }
state.roots = { [root_string] = { [relpath] = status_name } }
```

root と cwd は文字列キー、status のパスは forward slash の root 相対です。`remember()` は
取得結果を merge し、`clear_root()` / `forget()` は再取得時の stale state を破棄します。

## 5. VCS 検出

Git は対象ディレクトリから親方向へ `.git` を探します。`.git` がディレクトリなら通常の
リポジトリ、`gitdir: ` で始まるファイルなら worktree / submodule の root と判定します。
SVN は `.svn` ディレクトリを探します。両方が検出されたときは、開始位置に近い root を優先し、
同じ位置なら `detection.priority`（既定 `git`, `svn`）を使います。

通常の検出経路で Git/SVN のサブプロセスを起動せず、Yazi の filesystem API を使います。

## 6. Backend 契約

```lua
backend = {
  capabilities = { push = false, branch = false, switch = false },
  status_args = function(paths, options) end,
  fetch = function(root, paths, options)
    -- changed, excluded, err
  end,
}
```

Git は次を組み立てます。

```text
git --no-optional-locks -c core.quotePath= status --porcelain=v2 -z
    --untracked-files=all --ignored=matching -- <paths...>
```

porcelain v2 の rename / copy レコードは NUL フィールドを2つ消費するため、パーサはレコード種別
を見て original path を読み飛ばします。

SVN は次を組み立てます。

```text
svn status --xml --no-ignore [--ignore-externals] -- <paths...>
```

SVN の XML は限定的な属性パーサで処理し、named / numeric entity、`<lock>` 要素、tree conflict、
property-only modification を扱います。`fetch()` の返り値は Git/SVN とも
`changed, excluded, err` の3値に統一しています。

## 7. 状態優先度と表示

`core-status.lua` は次の優先度で状態を1文字へ集約します。

```text
conflict > missing > deleted > replaced > modified > property_modified
> added > untracked > locked > external > ignored > clean
```

`excluded` は Git ignored ディレクトリ内部の bookkeeping 用 sentinel で、描画前に `ignored` へ
変換します。記号は `config.signs`、先頭列の順序は `config.status.order`、テーマ色は
`th.vcs.<status>` から設定できます。

## 8. テスト戦略

- `lua tests/run.lua`: 設定マージ、パス、検出アルゴリズム、優先度・集約、Git/SVN パーサを検証
- 実 Git 結合テスト: modified、untracked、ignored、rename の実出力を検証
- 実 SVN 結合テスト: 作業コピーを生成し modified / unversioned の実出力を検証
- 結合テストの一時ディレクトリ、shell quote、cwd、file URL、cleanup は OS-aware helper に集約
- 実 Yazi: fetcher、`ya.sync` 状態、先頭列描画、手動 refresh をスモーク・目視確認

Lua interpreter がない環境では純粋 Lua テストを実行できません。また SVN CLI がない環境では
SVN 結合テストを skip します。TUI の色・位置、SVN external / obstructed / incomplete は別途実機確認が必要です。

## 9. 既知の制約と将来拡張

- Phase 2: Update、Commit、CLI Diff、CLI Log、Discard
- Phase 3: Git Push、Branch、Switch
- Phase 4: 外部 diff / log、Windows GUI、WSL パス変換、性能改善
- 既存 `git.yazi` と同時に status fetcher を有効にすると二重表示になる可能性があります
- 認証情報管理、Force Push、clean、stash などの破壊的・認証系機能は未実装です

## 10. 参照

- [ルート README](../README.md)
- [ユーザーマニュアル](users-manual.md)
- [要件定義](requirements.md)
- [プラグイン README](../vcs.yazi/README.md)
- [TODO / 完了記録](todo.md) / [done.md](done.md)
