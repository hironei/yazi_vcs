# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 1 実装（コミット `a6d2e4e`）。

本書は「何を作るか」（[requirements.md](requirements.md)）に対して「実際どう作ったか」を記録する。要件定義時点の想定と実装時に判明した制約・実測結果が食い違う箇所は、その理由を明記する。

---

## 1. モジュール構成

Yazi の `require()` は `plugins/{plugin}.yazi/{entry}.lua` にのみ解決され、エントリ名は kebab-case（`[0-9a-z-]`のみ）、サブディレクトリ不可（`yazi-runner/src/loader/loader.rs::explode_id_parts` で検証済み。requirements.md §5.2）。このためディレクトリ階層ではなく **ファイル名のプレフィックスで論理グループを表現する** フラット構成にした。

```
vcs.yazi/
├── main.lua           -- エントリポイント。setup / fetch / entry
├── config.lua          -- 既定値・deep_merge
├── core-path.lua        -- パス正規化（純粋関数）
├── core-detector.lua     -- VCSルート検出（純粋関数 + Yaziアダプタ）
├── core-status.lua       -- 状態優先度・集約ロジック（純粋関数）
├── core-state.lua        -- ya.sync永続ストレージ（Yazi専用）
├── core-notify.lua       -- 通知整形・送信
├── backend-git.lua       -- git status解析・実行
├── backend-svn.lua       -- svn status解析・実行
├── tests/                -- 素のluaで実行できる単体・結合テスト
├── README.md
└── LICENSE
```

`init.lua` は成果物に含めない。ユーザーの `~/.config/yazi/init.lua` から `require("vcs"):setup()` を呼ぶ前提（README参照）。

---

## 2. レイヤリング：純粋ロジック / Yazi依存

Yazi のプラグインAPI（`ya`, `Command`, `fs`, `ui`, `th`, `cx`, `Entity`）はグローバル変数として提供され、Yazi ランタイム外では未定義（`nil`）になる。そこで各ファイルは次のルールに従う。

| 単体テスト | lua tests/run.lua | test-configを含む純粋Luaの回帰テストと、両backendのパーサを検証 |
- 純粋ファイル（`core-path.lua`, `core-status.lua`, `core-detector.lua` の検出アルゴリズム部分, `backend-git.lua`/`backend-svn.lua` のパーサ部分）は Yazi API に一切触れず、`tests/*.lua` から素の `lua` で直接検証できる。
- Yazi 専用ファイル（`core-state.lua` の `ya.sync` 群、`core-notify.lua` の送信部、`main.lua` の `setup`/`fetch`/`entry`）は実 Yazi 上でのスモークテストでのみ検証できる（§7参照）。

この分離により、テストスイート（88件）の大半を素の `lua` で実行できている。

---

## 3. データフロー

```
Yazi fetcher (url="*" / url="*/")
        │
        ▼
main.lua : M:fetch(job)
        │  job.files[1].url.base/.parent → cwd
        ▼
core-detector.lua : M.detect(cwd, priority)
        │  .git / .svn を親方向へ探索（サブプロセス不使用）
        ▼
kind, root  ("git"|"svn", Url)
        │
        ▼
main.lua : job.files を root相対・forward-slashパスへ変換
        │  (Path.strip_prefix)
        ▼
backend-git.lua / backend-svn.lua : M.fetch(root_str, queried, options)
        │  Command(...):cwd(root):arg(status_args(paths, options)):output()
        │  → parse_status / parse_status_xml
        ▼
changed, excluded, err
        │
        ▼
core-status.lua : bubble_up / propagate_down / merge
        │  ディレクトリ集約・優先度解決
        ▼
main.lua : 未出力パスを "clean" で埋め戻し
        ▼
core-state.lua : State.remember(cwd, root, changed)  [ya.sync]
        │  state.dirs[cwd]=root, state.roots[root][relpath]=status
        ▼
main.lua : Entity:children_add(render_fn, order)
        │  State.root_of / State.status_of を毎フレーム参照
        ▼
先頭列に状態記号を描画
```

### 3.1 状態の持ち方

`core-state.lua` の永続テーブルは2段構成。

```lua
state.dirs  = { [cwd_abs_string] = root_abs_string }
state.roots = { [root_abs_string] = { [relpath] = status_name } }
```

`relpath` は常に forward-slash・root相対。Git はコマンド自体がこの形式で出力するためそのまま使え、SVN は実測により「渡したパスをそのまま返す」（後述4.1）ことが判明したため、渡す時点で root相対・forward-slash に統一している。

### 3.2 `ya.sync` の挙動（要注意点）

`ya.sync(function(state, ...) ... end)` の `state` 引数は「このブロックを**定義したファイル**自身がロードされたモジュールテーブル」に束縛される（`yazi-plugin/src/utils/sync.rs` の `current` = `rt.current_owned()` を実測・ソース確認）。つまり `core-state.lua` 内で定義した `ya.sync` ブロックはすべて `core-state.lua` 自身の返り値テーブルを共有ストレージとして使う。同期(sync)コンテキストから呼んでも非同期(async)コンテキストから呼んでも、Rust側が `blocking` フラグを見て自動的に直接呼び出し/チャネル経由呼び出しを切り替えるため、呼び出し側は区別を意識しなくてよい（同ファイル内で確認）。この性質により、`Entity:children_add` のレンダーコールバック（同期コンテキスト）から `State.status_of(...)` を毎フレーム呼んでも問題なく動作する。

---

## 4. 実装時に判明した仕様上の発見

要件定義（requirements.md）作成時点では未検証・推測だった箇所を、実装時に実機（Git 2.x, SVN 1.14.5, Yazi 26.5.6）で確認し、設計に反映した。

### 4.1 SVN はターゲットパスを「渡した形のまま」返す（Gitとの重要な差異）

`git status` はどんな形でパスを渡しても、常に **cwd相対** のパスを返す。一方 `svn status --xml` は **渡した形をそのまま**返す——絶対パスを渡せば絶対パスが返る（実測: `C:\Users\...\modified.txt` がそのままXMLの `path` 属性に出現）。この非対称性に気づかずに `job.files` の絶対URLをそのまま両バックエンドへ渡すと、SVN側だけ root相対キー前提が壊れる。対策として、`main.lua` はどちらのバックエンドに対しても **事前に root相対・forward-slashへ変換したパス** のみを渡す（`backend-git.lua:31`, `backend-svn.lua:114` のコメント参照）。

### 4.2 Git porcelain v2 の rename レコードは NUL フィールドを2つ消費する

`git status --porcelain=v2 -z` の rename/copy レコード（先頭 `2`）は、他のレコードと違い **NUL区切りフィールドを2つ**使う（`<path>` フィールドの直後に `<origPath>` フィールドが続く）。実測: `2 R. N... ... R100 new.txt\0old.txt\0`。単純に「NULで割って1レコード1フィールド」と実装すると、rename の直後のレコードが必ず化ける。`backend-git.lua` の `parse_status` はレコード種別を先に判定し、`2` のときだけ2フィールド消費するよう実装している。

### 4.3 SVN の `<lock>` はXML要素であり属性ではない

当初は `wc-locked="true"` のような属性を想定していたが、実際には `<wc-status>` の子要素として `<lock><token>...</token>...</lock>` の形で出現する（実測）。`backend-svn.lua` の `classify` は `body:find("<lock[%s>]")` で子要素の有無を判定する。

### 4.4 `--` オプション終端は SVN でも必須

`-` から始まるファイル名（例: `-dashfile.txt`）を渡す際、`svn status` は `--` がないとパスをオプションとして誤解釈する（実測、requirements.md §26.4 の未検証事項を解消）。`backend-svn.lua:status_args` は常に `--` を挟む。

### 4.5 `Entity:children_add` で先頭列描画は可能

要件定義初版は「先頭列表示は困難な場合がある」としていたが、`Entity` の組み込み子要素（`padding` が `order=1000`）より小さい `order` を指定すれば先頭列に描画できることをソース確認（`yazi-plugin/preset/components/entity.lua`）。`main.lua` は `cfg.status.order`（既定 `500`）で `padding` より前に描画する。

---

## 5. バックエンド抽象化

`backend-git.lua` / `backend-svn.lua` は共通のstatus backend契約を実装する。

```lua
M.capabilities = { push = bool, branch = bool, switch = bool }
M.status_args(paths, options) -> string[]
M.fetch(root, paths, options) -> (changed, excluded, err)
```

SVNはGitのような`excluded`ディレクトリを返さないため、`fetch()`の成功時に空テーブルを返す。これにより`main.lua:M:fetch`はbackend種別による返り値の分岐なしで処理できる。SVN固有の`status.ignore_externals`はbackend options経由で`--ignore-externals`の有無へ反映する。

`capabilities`テーブルはPhase 2/3（Push/Branch/SwitchのUIをSVNで無効化する、requirements.md §18）で使う設計だが、Phase 1時点では参照箇所がない（意図的な先行実装であり、既知のレビュー指摘でも「欠陥ではない」）。

## 6. 状態の優先度と集約

`core-status.lua` の `M.CODES` は各状態名に一意の優先度数値を割り当てる（同数値の状態を作らない——git.yazi の実装がまさにこの制約に依っている）。

```
conflict(12) > missing(11) > deleted(10) > replaced(9) > modified(8)
> property_modified(7) > added(6) > untracked(5) > locked(4)
> external(3) > ignored(2) > clean(0)
```

`unknown(100)` と `excluded(99)` は表示用ではない内部センチネル。`unknown` は「まだfetchされていない」、`excluded` は「まるごとignoreされたディレクトリの内部にいる」ことを表す git.yazi 由来のブックキーピング値で、本来は表示前に `ignored` へ変換される設計（`core-status.lua` 冒頭コメント）。この変換は`core-status.lua:M.display_name`で行い、描画層が`excluded`を直接参照しない。

`bubble_up` はファイル単位の変更を祖先ディレクトリへロールアップし（ignoreされた変更は伝播させない）、`propagate_down` は「まるごとignoreされたディレクトリ」を fetch 対象の直下エントリとして表示するか、fetch対象自身がその内部にあるかを判定する。いずれも git.yazi の `bubble_up`/`propagate_down` を移植・一般化したもの（MITライセンス）。

---

## 7. テスト戦略

| 種別 | 実行方法 | 内容 |
|---|---|---|
| 単体テスト | lua tests/run.lua | test-configを含む純粋Luaの回帰テストと、両backendのパーサを検証 |
| 結合テスト（実バイナリ） | 同上（`git`/`svn` がPATHにあれば自動実行） | 一時リポジトリ/作業コピーを作成し、実CLI出力をパーサに通す |
| スモークテスト | 実Yazi起動 + 一時的な `ya.dbg` 計装 | `%APPDATA%\yazi\config\plugins\vcs.yazi` へジャンクション接続し、Gitリポジトリ・SVN作業コピー・非VCSディレクトリの3パターンで `fetch()` がエラーなく完走することを確認済み（計装は確認後に削除） |
| 未実施 | — | 画面上の記号の色・位置の目視確認（TUIのため自動化不可、ユーザー自身の確認が必要） |

---

## 8. 既知の制約・未解決事項

- /code-review medium で検出したIssue #1〜#6は修正済み。残る未検証事項はSVN externals等の実働fixtureとTUI目視確認。
- SVNの `external` / `obstructed` / `incomplete` は `svn help status` の文書のみに基づき、実働作業コピーでの再現は未実施（requirements.md §26.4）。
- Phase 2以降（Update/Commit/Diff/Log/Discard/Push/Branch/Switch）は未実装。

---

## 9. 参照

- [requirements.md](requirements.md) — 要件定義（本書が「as-built」として差分を説明する対象）
- [../vcs.yazi/README.md](../vcs.yazi/README.md) — インストール手順・設定例・既知の制限（ユーザー向け）
- [todo.md](todo.md) / [done.md](done.md) — 作業記録
