# Yazi向け Git／SVN 統合VCSプラグイン 要件定義

- 対象Yaziバージョン：26.5.6 以降
- 最終更新：2026-08-11

---

## 0. 本改訂について

初版の要件定義に対し、Yazi 26.5.6 の実装（`yazi-runner`／`yazi-plugin` のソース）、公式`git.yazi`プラグイン、および Git CLI の実測結果を突き合わせて検証し、以下を修正した。

### 0.1 実装不可能だったため変更した項目

| 項目 | 初版の記述 | 問題 | 対応 |
|---|---|---|---|
| モジュール構成 | `core/`、`backends/`、`actions/`サブディレクトリ | Yaziの`require`はネストしたパスを解決できない | §5.2 をフラット構成へ変更 |
| ステータス取得契機 | 独自のキャッシュ／debounce機構 | Yaziのfetcher機構を使わないと、そもそも起動契機が存在しない | §8.7、§9、§24 をfetcher前提へ変更 |
| Git Commit | `git commit --file=<f> -- <targets>`で「自動`git add`を行わない」 | 同コマンドは指定パスを暗黙にstageする（実測で確認） | §11.2、§20、§25 を実挙動に合わせて修正 |

### 0.2 検証で判明した仕様上の欠落

| 項目 | 内容 | 対応 |
|---|---|---|
| Ignored状態 | `git status --porcelain=v2 -z -uall`はignoredを出力しない（実測） | §8.4 に`--ignored=matching`を追加 |
| rename解析 | `-z`+porcelain v2のrenameレコードはNUL区切りフィールドを2つ消費（実測） | §8.4、§26.1 に明記 |
| タイムアウト | Yaziの`Command`にタイムアウトAPIは存在しない | §21.1 に実現方式を明記 |
| キー割り当て | `v`はYazi既定の`visual_mode` | `v`単独を潰さない任意のプレフィックスを設定例へ記載 |
| 外部diff | `--diff-cmd difft`は引数規約が合わず動作しない | §12.5 にラッパー必須を明記 |

### 0.3 検証で判明した「初版より強くできる」項目

| 項目 | 内容 | 対応 |
|---|---|---|
| 先頭列表示 | `Entity:children_add`により真の先頭列描画が可能 | §8.1 の留保を削除し必須要件化 |
| ルート検出 | サブプロセス不要でLuaのみで判定可能 | §6.2 を変更 |
| index衝突回避 | `--no-optional-locks`が必要 | §8.4、§27 に追加 |
| バージョン整合 | Yaziは`--- @since`ヘッダを検査する | §5.4 を新設 |

### 0.4 未検証事項

本改訂の検証環境に SVN CLI が導入されていないため、**SVN に関する記述は文書ベースでの確認にとどまる**。実装着手前に §26.4 の事前検証を実施すること。

---

## 1. 概要

Yazi上でGitおよびSubversion（SVN）の主要操作を統一的に実行できるプラグインを開発する。

プラグインはGitとSVNを別々のUIとして提供するのではなく、共通のVCS操作インターフェースを提供し、対象ディレクトリのVCS種別を自動判定して適切なCLIコマンドを実行する。

Git固有機能については、共通操作とは分離した形で提供する。

---

## 2. 目的

- Yazi上でファイルを確認しながらGit／SVN操作を実行できるようにする
- GitとSVNで可能な限り操作感とキー体系を統一する
- Git／SVN CLIを直接利用し、独自のVCS実装を持たない
- 外部エディタ、diffツール、ログビューアを任意設定可能にする
- Windows、Git Bash、WSL、Linux環境での利用を考慮する
- 破壊的操作に対して誤操作防止を行う
- 将来的に他VCSを追加可能な構造とする

---

## 3. 対象環境

### 3.1 必須環境

- Yazi 26.5.6 以降
- Git CLI 2.30 以降（`git switch`／`git restore`が非experimentalであること）
- SVN CLI 1.9 以降（`svn info --show-item`が利用可能であること）
- Windows 11またはLinux

### 3.2 想定シェル

- Git Bash
- WSL Bash／Zsh
- Linux Bash／Zsh
- Windows Native環境

### 3.3 任意依存

以下は設定された場合のみ使用する。

- エディタ：Vim、Neovim、Visual Studio Code、任意コマンド
- pager：less、bat、任意コマンド
- diffツール：difftastic、delta、WinMerge、Beyond Compare、TortoiseGitMerge、TortoiseMerge、任意コマンド
- ログビューア：lazygit、tig、TortoiseGitProc、TortoiseProc、任意コマンド

---

## 4. スコープ

### 4.1 対象機能

#### Git／SVN共通

- VCS自動判定
- リポジトリ／作業コピールート検出
- ステータス表示
- ステータス再取得
- Update
- Commit
- Diff
- Log
- ローカル変更の破棄
- 複数ファイル選択への操作
- 外部コマンド呼び出し
- 実行結果通知
- 実行後の表示更新

#### Git固有

- Push
- Branch一覧
- Branch作成
- Branch名称変更
- Branch削除
- Branch切替
- リモート追跡ブランチからのローカルBranch作成

### 4.2 初期スコープ外

- Git Force Push
- Git clean
- Git commit履歴に対する`git revert`
- Git rebase
- Git merge
- Git cherry-pick
- Git stash
- Git tag管理
- Git submodule管理
- SVN branch／tag作成
- SVN merge
- SVN switch
- SVN lock／unlock
- SVN changelist
- SVN externals配下の再帰処理
- GUIによるコンフリクト解消
- 認証情報管理
- Git／SVN CLIのインストール

---

## 5. 基本設計方針

### 5.1 プラグイン名

仮称：

```text
vcs.yazi
```

### 5.2 モジュール構成

**【初版から変更】**

Yaziのモジュール解決は以下の制約を持つ（`yazi-runner/src/loader/loader.rs::explode_id_parts`）。

- モジュールIDは**最初の`.`でのみ**分割され、`plugins/{plugin}.yazi/{entry}.lua`へ解決される
- `plugin`部・`entry`部はいずれも kebab-case 必須。使用可能な文字は `[0-9a-z-]` のみ（`yazi-shared/src/bytes.rs::kebab_cased`）
- したがって**サブディレクトリは使用できず、`_`（アンダースコア）もファイル名に使用できない**
- `require(".name")`で同一プラグイン内の相対参照が可能（`require.rs::absolute_id`）

構成：

```text
vcs.yazi/
├── main.lua              -- エントリポイント。setup / entry / fetch を export
├── config.lua            -- 既定値とユーザー設定のマージ
├── core-detector.lua     -- VCS種別・ルート検出
├── core-runner.lua       -- 外部コマンド実行ラッパー
├── core-targets.lua      -- 操作対象ファイル決定
├── core-external.lua     -- エディタ／pager／外部ツール起動
├── core-path.lua         -- パス正規化・変換
├── core-notify.lua       -- 通知整形
├── core-state.lua        -- ya.sync 越しの状態read/write
├── backend-git.lua
├── backend-svn.lua
├── action-status.lua
├── action-update.lua
├── action-commit.lua
├── action-diff.lua
├── action-log.lua
├── action-discard.lua
├── action-push.lua
├── action-branch.lua
├── action-switch.lua
├── tests/                -- Lua外部テストランナーから読む。require対象外
├── README.md
└── LICENSE
```

補足：

- `init.lua`は**プラグインの成果物ではない**。ユーザーの`~/.config/yazi/init.lua`から`require("vcs"):setup{}`を呼ぶ形とし、その記述例をREADMEへ掲載する
- `tests/`配下はYaziの`require`対象ではなく、外部のLuaテストランナー（busted等）からのみ読み込む。よってサブディレクトリ制約は適用されない

### 5.3 Backendインターフェース

共通Backendは以下の責務を持つ。

```lua
backend = {
    detect_root = function(url) end,
    parse_status = function(raw) end,
    status_command = function(root, paths) end,
    update = function(root, options) end,
    commit = function(root, targets, message_file, options) end,
    diff = function(root, targets, options) end,
    log = function(root, targets, options) end,
    discard = function(root, targets, options) end,

    capabilities = {
        push = false,
        branch = false,
        switch = false,
    },
}
```

Git固有機能は同一テーブル上に実装し、`capabilities`で有効・無効を判定する。初版にあった`git_backend`という別インターフェース定義は`capabilities`と責務が重複するため廃止する。

```lua
-- backend-git.lua が capabilities = { push = true, branch = true, switch = true }
-- を宣言したうえで、以下を追加で実装する
push          = function(root, options) end,
list_branches = function(root, options) end,
create_branch = function(root, name, start_point, options) end,
rename_branch = function(root, old_name, new_name, options) end,
delete_branch = function(root, name, options) end,
switch_branch = function(root, name, options) end,
```

### 5.4 バージョン互換宣言

**【新設】**

Yaziは`Loader::compatible_or_error`でプラグイン先頭の`--- @since`ヘッダを検査し、非互換時に明示エラーを出す。

`main.lua`の1行目に以下を記述すること。

```lua
--- @since 26.5.6
```

### 5.5 実行コンテキストの制約

**【新設】**

- Yaziのグローバル`require`は非同期関数として実装されている（`require.rs::install`）。したがって**`ya.sync()`ブロック内から`require`を呼び出してはならない**
- `Command:output()`等のプロセス実行APIは非同期コンテキスト専用
- UI描画（`Entity`／`Linemode`の子関数）は同期コンテキストで実行される。ここでは事前に`ya.sync`で書き込まれた状態テーブルの参照のみを行い、I/Oを行わない
- 設計上、以下の3層に分離する
  1. 非同期層：CLI実行と出力解析（`core-runner`、`backend-*`）
  2. 同期状態層：`ya.sync`でのstate読み書きと`ui.render()`（`core-state`）
  3. 描画層：stateの参照のみ（`main.lua`内のEntity子関数）

---

## 6. VCS自動判定

### 6.1 判定仕様

現在ディレクトリから親方向へ探索し、`.git`または`.svn`を検出する。

### 6.2 Git判定

**【初版から変更】**

初版は`git -C <path> rev-parse --show-toplevel`を第一候補としていたが、ディレクトリ移動のたびにプロセス起動が発生し §27 の性能要件と競合する。公式`git.yazi`と同様に、**Lua APIのみで判定する**。

1. 対象ディレクトリから親方向へ`.git`を探索する
2. `fs.cha()`で存在を確認する
3. ディレクトリであればリポジトリルートと判定する
4. ファイルであれば先頭8バイトを読み、`"gitdir: "`であればworktreeまたはsubmoduleとしてルートと判定する

これにより「`.git`はディレクトリとは限らない」問題をサブプロセスなしで解決する。

`git rev-parse --show-toplevel`は、上記で判定できない例外ケースの診断用フォールバックとしてのみ使用し、通常経路では実行しない。

### 6.3 SVN判定

1. 対象ディレクトリから親方向へ`.svn`ディレクトリを探索する（SVN 1.7以降は作業コピールートに1つだけ存在する）
2. 検出できた場合、そのディレクトリを作業コピールートとする

`svn info --show-item wc-root <path>`は、上記で判定できない場合の確認用フォールバックとする（SVN 1.9以降が必要）。

### 6.4 両方が検出された場合

現在位置に最も近いルートを優先する。同一位置で両方が検出された場合は設定の優先順位に従う。

```lua
detection = {
    priority = { "git", "svn" },
}
```

---

## 7. 対象ファイル決定

操作対象は次の優先順位で決定する。

1. Yaziで選択中の複数ファイル
2. Hover中のファイル
3. カレントディレクトリ

操作対象の選択優先順位は全操作で固定する。選択中の項目（複数選択時は全件）を優先し、選択がなければhover中の項目、最後にカレントディレクトリを使用する。操作ごとのscope設定は初期リリースの対象外とする。

- 対象パスは必ずVCSルート配下であることを検証する
- 空白、日本語、記号を含むパスを正しく処理する
- シェル文字列連結ではなく、必ず`Command:arg()`へ引数配列として渡す

---

## 8. ステータス表示

### 8.1 表示要件

**【初版から変更】**

初版は「完全な先頭列がYazi API上困難な場合はlinemode領域への表示を許容する」としていたが、`Entity:children_add(fn, order)`が利用可能であり（`yazi-plugin/preset/components/entity.lua`）、先頭列描画は実現可能である。

Entityの組み込み子要素の`order`は以下のとおり。

```lua
_children = {
    { "padding",    id = 1, order = 1000 },
    { "icon",       id = 2, order = 2000 },
    { "prefix",     id = 3, order = 3000 },
    { "highlights", id = 4, order = 4000 },
    { "found",      id = 5, order = 5000 },
    { "symlink",    id = 6, order = 6000 },
}
```

要件：

- **`Entity:children_add`に`order < 1000`（既定値500）を指定し、`padding`より前＝行の先頭列に1文字の状態記号を表示する**
- `order`は設定で変更可能とする
- Git／SVNで意味が共通する状態は同じ記号を使用する
- SVN固有状態は追加記号として保持する
- 記号と装飾は設定可能とし、装飾は`th.vcs.*`経由でテーマから上書き可能とする
- ディレクトリにも状態記号を表示する（§8.6）

### 8.2 共通状態

| 状態 | 記号 | Git | SVN |
|---|---:|---|---|
| Modified | `M` | modified | modified |
| Added | `A` | added／staged | added |
| Deleted | `D` | deleted | deleted |
| Untracked | `?` | untracked | unversioned |
| Ignored | `I` | ignored | ignored |
| Conflict | `C` | unmerged | conflicted |
| Missing | `!` | deleted相当 | missing |
| Replaced／Renamed | `R` | renamed | replaced |
| External | `X` | 原則対象外 | external |
| Clean | 空白 | clean | normal |

### 8.3 SVN固有状態

| 状態 | 記号候補 |
|---|---:|
| Obstructed／種別不整合 | `~` |
| Locked | `L` |
| Property-only modified | `P` |

複数状態を持つ場合は、優先度の高い状態を1文字で表示する。

推奨優先度：

```text
Conflict
> Missing／Deleted
> Modified／Replaced
> Added／Untracked
> Locked／External
> Ignored
> Clean
```

### 8.4 Gitステータス取得

**【初版から変更】**

コマンド：

```bash
git --no-optional-locks -c core.quotePath= status --porcelain=v2 -z --untracked-files=all --ignored=matching -- <paths...>
```

各オプションの根拠：

| オプション | 根拠 |
|---|---|
| `--no-optional-locks` | ファイラが背後で`status`を回すとindexロックを取得し、ユーザーが別端末で実行中のgitコマンドと衝突する。公式`git.yazi`も指定している |
| `--porcelain=v2` | 機械可読かつ安定した形式 |
| `-z` | NUL区切り。**`-z`指定時gitはパスのクォートを無効化する**ため、日本語・空白を含むパスがそのまま取得できる（受入条件19の前提） |
| `--untracked-files=all` | 未追跡ファイルを個別に取得 |
| `--ignored=matching` | **初版のコマンドではignoredが一切出力されず、§8.2のIgnored状態を表示できないことを実測で確認したため追加** |
| `-- <paths...>` | fetcherが受け取った表示中ファイルのみに限定し、大規模リポジトリでの走査量を抑える |

#### 8.4.1 解析上の注意（必須）

`-z`とporcelain v2を組み合わせた場合、**rename／copyレコード（先頭が`2`）だけはNUL区切りフィールドを2つ消費する**。実測例（NULを`|`で表示）：

```text
2 R. N... 100644 100644 100644 <sha> <sha> R100 new.txt|old.txt|
```

一方、通常レコード（先頭`1`）、未追跡（`?`）、ignored（`!`）は1レコード1フィールドである。

「NULで分割して1件＝1エントリ」とする実装は rename で必ず破綻する。パーサはレコード種別を先に判定し、`2`の場合のみ追加フィールドを読み進めること。§26.1 の必須テスト項目とする。

#### 8.4.2 簡易形式

porcelain v1（`--porcelain=v1 -z`）は初期リリースの対象外とし、v2のみを実装・検証する。

### 8.5 SVNステータス取得

**【初版から変更】**

コマンド：

```bash
svn status --xml --no-ignore --ignore-externals <path>
```

- `--no-ignore`：**`svn status`は既定でignoredを出力しないため、§8.2のIgnored状態表示に必要**
- `--ignore-externals`：§27 の性能要件に基づく既定
- clean（normal）状態は`svn status`が出力しないため、`-v`を付けずに「出力に現れないもの＝clean」として扱う。`-v`は大規模作業コピーで出力量が過大になるため既定では使用しない

XMLから最低限以下を取得する。

- path
- item
- props
- revision
- copied
- switched
- tree-conflicted

外部XMLライブラリへの必須依存は避ける。簡易XMLパーサーを実装する場合は、対象要素と属性を限定し、エスケープ処理（`&amp;` `&lt;` `&gt;` `&quot;` `&apos;`、および数値文字参照）を正しく行う。

> 未検証：本項のSVNコマンドは文書ベースでの確認にとどまる。§26.4 で実機確認すること。

### 8.6 ディレクトリ状態集約

配下に変更があるディレクトリにも状態記号を表示する。

```text
M src/
M src/main.c
  src/util.c
```

- 子孫の状態を親ディレクトリへ集約する
- 集約時も §8.3 の状態優先度を適用する
- ignoredは集約対象外とする（ignoredファイルの存在で親ディレクトリをマークしない）
- ignoredディレクトリ配下は、そのディレクトリ自体をignoredとして扱い、配下を個別に走査しない

### 8.7 取得契機とキャッシュ

**【初版から全面変更】**

初版は独自のキャッシュ・debounce・多重実行抑止機構を設計していたが、Yaziには**fetcher機構**が存在し、公式`git.yazi`はこれを利用している。初版の設計では、そもそもディレクトリ表示時にステータスを計算する起動契機が存在しない。

#### 8.7.1 fetcherとして登録する

`main.lua`は`fetch`関数をexportし、ユーザーの`~/.config/yazi/yazi.toml`へ以下を登録する（README記載必須）。

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

`id`はYazi 26.1.22より新しい版では不要。READMEでその旨を注記する。

#### 8.7.2 fetchの責務

```lua
---@type UnstableFetcher
local function fetch(_, job)
    -- job.files には現在表示中のファイル群のみが渡る
end
```

- 起動契機、実行間隔、重複起動の抑止はYaziのfetcherスケジューラが担う。プラグイン側で独自のdebounceタイマーを実装しない
- `job.files`に含まれるパスのみをCLIへ渡し、リポジトリ全体を走査しない
- CLI出力の解析後、`ya.sync`関数経由でstateへ書き込み、`ui.render()`を呼ぶ
- 出力に現れなかったパスは明示的にcleanへリセットし、stateに古い状態を残さない
- 戻り値は`(boolean, Error?)`。回復不能なエラー時は`true`（再試行不要）を返す

#### 8.7.3 state構造

```lua
st.dirs  = { [dir] = root }              -- ディレクトリ→VCSルートの逆引き
st.roots = { [root] = { kind = "git"|"svn", files = { [relpath] = code } } }
```

#### 8.7.4 明示的な破棄

Commit、Update、Discard、Switch、Push成功後は、対象ルートのstateを破棄したうえで再fetchを要求する（§9）。

設定：

```lua
status = {
    aggregate_directories = true,
    ignore_externals = true,
    order = 500,
}
```

初版にあった`cache`および`debounce_ms`は、fetcher機構が担うため削除する。

---

## 9. Status再取得

手動でステータスを再取得できること。

処理内容：

1. 現在のVCSルート判定
2. 対象ルートのstate破棄
3. `ya.emit("refresh", {})`によりYaziへ再取得を要求する
4. fetcherが再実行され、表示が更新される
5. 成否通知

プラグインからCLIを直接叩いて描画するのではなく、fetcher経路を再走させることで、通常経路と再取得経路の挙動を一致させる。

---

## 10. Update

### 10.1 共通UI名

```text
Update
```

### 10.2 Git

既定コマンド：

```bash
git pull --ff-only
```

理由：

- 暗黙のmerge commit作成を避ける
- fast-forward不可の場合は処理を停止する
- ユーザーに明示的な判断を促せる

設定で変更可能とする。

```lua
update = {
    git = { "git", "pull", "--ff-only" },
}
```

### 10.3 SVN

```bash
svn update
```

対象がファイルまたは選択項目の場合も、設定により対象指定を許容する。既定では作業コピールートまたはカレントディレクトリを更新する。

### 10.4 実行後

- 終了コードを確認する
- 標準出力／標準エラーを表示する
- 成功時は §8.7.4 に従いstateを破棄し再fetchする
- コンフリクト発生時は警告通知する

### 10.5 認証

Update は認証入力を要求しうる。§21.2 のターミナル占有機構（`ui.hide()`）を用いて実行する。

---

## 11. Commit

### 11.1 基本フロー

1. 対象ファイル決定
2. VCSルート判定
3. 一時メッセージファイル作成
4. `ui.hide()`でターミナルを占有し、設定されたエディタを起動
5. エディタ終了待ち
6. permitを`drop()`してTUIへ復帰
7. メッセージ内容確認
8. 空メッセージならキャンセル
9. Commitコマンド実行
10. 結果表示
11. state破棄と再fetch

### 11.2 Git

**【初版から変更 — 初版の記述は事実誤認】**

初版は`git commit --file=<f> -- <targets>`について「初期版では自動`git add`を行わない」「選択ファイルが未stageの場合、Git CLIの結果をそのまま表示する」としていたが、実測により誤りであることを確認した。

```text
$ echo mod >> t.txt              # 未stageの変更
$ git commit --file=/tmp/m.txt -- t.txt
[main 0b2956b] msg
 1 file changed, 1 insertion(+)  # rc=0、コミットされた
```

`git commit`にpathspecを渡すと git は `--only` モードで動作し、**指定パスの作業ツリー内容をその場でstageしてコミットする**。したがって初版の §11.2、§20 の`auto_stage_git = false`、§25 の「自動stage禁止」は、§11.2 自身が指定するコマンドによって破られていた。

本改訂では**path モードを既定とする**。理由：

- SVNのcommitは元来パス指定であり、pathモードを既定とすることで §2「GitとSVNで可能な限り操作感を統一する」を満たせる
- stage対象は「ユーザーがYazi上で選択し、確認ダイアログに列挙されたパス」に限定されるため、暗黙的で予期しない挙動にはならない
- pathモードは**index上の他のstage済みファイルをコミットしない**ため、作業中のstageを巻き込む事故は発生しない

既定（`commit.git_mode = "paths"`）：

```bash
git commit --file=<message-file> -- <targets...>
```

代替（`commit.git_mode = "staged"`）：

```bash
git commit --file=<message-file>
```

要件：

- 確認画面に「対象パスは自動的にstageされる」旨を明示する
- `git_mode = "staged"`では対象パスを渡さず、stage済みの内容のみをコミットする
- 未追跡ファイルをpathspecに含めた場合、gitは`pathspec did not match`で失敗する。この場合は事前に検出し、「未追跡ファイルは`git add`が必要」と通知する

将来拡張として以下を分離可能とする。

- Stage selected files（`git add`のみ）
- Unstage selected files

### 11.3 SVN

```bash
svn commit --file=<message-file> -- <targets...>
```

> 未検証：SVNのサブコマンドが`--`をオプション終端として受理するかを §26.4 で確認すること。受理しない場合、パスが`-`で始まるケースの回避策（`./`前置）を実装する。

### 11.4 エディタ設定

```lua
editor = {
    command = "nvim",
    args = {},
    wait = true,
}
```

Visual Studio Code例：

```lua
editor = {
    command = "code",
    args = { "--wait" },
    wait = true,
}
```

エディタは §21.2 に従い、`stdin`／`stdout`／`stderr`を`Command.INHERIT`に設定したうえで`ui.hide()`配下で起動する。

### 11.5 一時ファイル

- OS標準の一時ディレクトリを利用する
- ファイル名衝突を避ける
- Commit終了後に削除する
- エラー時も可能な限り削除する
- UTF-8で扱う
- ファイルパーミッションは所有者のみ読み書き可能とする

### 11.6 キャンセル条件

以下の場合はCommitを実行しない。

- エディタ起動失敗
- エディタ異常終了（終了コード非0）
- メッセージが空（空白・コメント行のみを含む）
- ユーザーキャンセル
- 対象ファイルなし
- VCSルート検出失敗

---

## 12. Diff

### 12.1 モード

- CLI／pager表示
- 外部コマンド表示

### 12.2 Git CLI

```bash
git diff -- <targets...>
```

必要に応じて設定でstaged diffを追加可能とする。

```bash
git diff --cached -- <targets...>
```

初期版では通常diffのみ必須。

### 12.3 SVN CLI

```bash
svn diff -- <targets...>
```

### 12.4 pager

標準出力を設定されたpagerへ渡す。

```lua
pager = {
    command = "less",
    args = { "-R" },
}
```

pagerは §21.2 のターミナル占有機構配下で起動する。pager未設定または起動失敗の場合は、出力を一時ファイルへ書き出し、エディタで開くか通知で要約を示す。

### 12.5 外部Diff

**【初版から変更】**

VCSごとにコマンドテンプレートを設定可能とする。

```lua
diff = {
    git_external = {
        command = "git",
        args = { "difftool", "--no-prompt", "--", "{targets}" },
    },
    svn_external = {
        command = "svn",
        args = { "diff", "--diff-cmd", "svn-difft-wrapper", "--", "{targets}" },
    },
}
```

**重要な制約（初版の設定例は動作しない）：**

- `svn diff --diff-cmd <prog>`は、`<prog>`を**SVN固定の引数規約**（`-u -L <label1> -L <label2> <file1> <file2>`）で起動する。difftastic（`difft`）もdeltaもこの引数を受け付けないため、**ラッパースクリプトが必須**である。ラッパー例をREADMEへ掲載すること
- `git difftool`は`--no-prompt`だけでは不足で、`diff.tool`および必要に応じて`difftool.<tool>.cmd`のGit設定が前提となる。プラグインはこれを設定せず、未設定時のgitのエラーをそのまま提示する

使用可能なプレースホルダー：

- `{root}`
- `{file}`
- `{targets}`
- `{revision}`

`{targets}`は単一文字列へ連結せず、複数引数へ安全に展開する。

---

## 13. Log

### 13.1 モード

- CLI／pager表示
- 外部コマンド表示

### 13.2 Git CLI

リポジトリ全体：

```bash
git log --decorate --oneline --graph --all
```

対象ファイル指定：

```bash
git log --decorate --oneline --graph -- <targets...>
```

対象ファイルがある場合、`--all`は既定で付与しない（グラフが対象外ブランチで埋まり可読性が落ちるため）。設定で変更可能とする。

### 13.3 SVN CLI

```bash
svn log -- <targets...>
```

対象未指定の場合はカレントディレクトリまたは作業コピールートを対象とする。

### 13.4 外部ログビューア

```lua
log = {
    git_external = {
        command = "lazygit",
        args = {},
    },
    svn_external = {
        command = "TortoiseProc.exe",
        args = { "/command:log", "/path:{file}" },
    },
}
```

`lazygit`、`tig`は対話型TUIであるため §21.2 のターミナル占有機構配下で起動する。`TortoiseProc.exe`等のGUIツールは非占有で起動し、終了を待たない。この区別を設定可能とする。

```lua
log = {
    git_external = { command = "lazygit", args = {}, interactive = true },
    svn_external = { command = "TortoiseProc.exe", args = { ... }, interactive = false },
}
```

Windows外部コマンドへ渡す場合は §22 に従いパス変換する。

---

## 14. Discard Changes

### 14.1 UI名

ユーザー向け名称：

```text
Discard changes
```

内部アクション名は`discard`とする。`Revert`という名称はGitの`git revert`と混同するため、UIの主名称には使用しない。

### 14.2 Git

通常の作業ツリー変更破棄：

```bash
git restore -- <targets...>
```

初期版では以下を別操作または対象外とする。

- `git restore --staged`
- `git restore --source=HEAD --staged --worktree`
- `git clean`
- `git revert <commit>`

未追跡ファイルを対象に含めた場合、`git restore`は`pathspec did not match any file(s) known to git`（終了コード1）で失敗することを実測で確認済み。事前に未追跡ファイルを対象から除外し、除外した旨を通知する。

### 14.3 SVN

ファイル：

```bash
svn revert -- <targets...>
```

ディレクトリ再帰：

```bash
svn revert --depth=infinity -- <directory>
```

初版の`--recursive`は`--depth=infinity`の非推奨エイリアスであるため、後者を使用する。

### 14.4 安全確認

Discardは必ず確認ダイアログを表示する。`ya.confirm{ pos, title, body }`を使用する。

ファイルの場合：

```text
Discard local changes in 3 selected files?
These changes cannot be restored by Git/SVN.

[Confirm] [Cancel]
```

ディレクトリ再帰の場合は`ya.input`によるタイプ確認を行う。

```text
Recursively discard all local changes under:
src/

Type "revert" to continue:
```

### 14.5 制約

- Git未追跡ファイルは削除しない
- SVN未管理ファイルは削除しない
- 自動バックアップしない
- 実行前に対象一覧を表示する
- コマンド失敗時は成功扱いしない
- 実行後にstateを破棄し再fetchする

---

## 15. Git Push

### 15.1 基本処理

```bash
git push
```

### 15.2 upstream確認

現在ブランチ：

```bash
git branch --show-current
```

出力が空の場合はdetached HEADと判定する。

upstream確認：

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{upstream}
```

終了コード非0であればupstream未設定と判定する。

### 15.3 upstream未設定

remote一覧：

```bash
git remote
```

remote選択後：

```bash
git push --set-upstream <remote> <branch>
```

```lua
git = {
    push = {
        default_remote = "origin",
        set_upstream_if_missing = true,
    },
}
```

### 15.4 安全要件

初期版では以下を実行しない。

- `--force`
- `--force-with-lease`
- `--all`
- `--tags`
- remote branch削除

detached HEADではPushを実行せず、エラー通知する。

認証入力が必要な場合は §21.2 のターミナル占有機構を用い、Git CLIの標準挙動に委ねる。

---

## 16. Git Branch

### 16.1 Branch一覧

ローカルBranch一覧：

```bash
git branch --format=%(refname:short)%09%(HEAD)%09%(upstream:short)%09%(upstream:trackshort)
```

`%09`（TAB）がfor-each-ref形式で正しく展開されることを実測で確認済み。

リモートも含める場合：

```bash
git branch --all --format=...
```

表示項目：

- Branch名
- 現在Branch
- upstream
- ahead／behind
- local／remote区分

選択UIは`ya.input`または`ya.which`で実装する。

### 16.2 Branch作成

Branch作成のみ：

```bash
git branch <new-branch> [<start-point>]
```

作成と同時に切替：

```bash
git switch -c <new-branch> [<start-point>]
```

ユーザーに以下を入力させる。

- 新Branch名
- 開始点
- 作成後に切り替えるか

### 16.3 Branch名検証

```bash
git check-ref-format --branch <branch-name>
```

- 終了コード0で有効、非0で無効と判定する
- **注意**：`--branch`は単なる検証ではなく`@{-1}`等の相対参照を**展開**する。ユーザー入力が`@`または`-`で始まる場合は、CLIを呼ぶ前にプラグイン側で拒否する
- 検証失敗時は作成しない

### 16.4 Branch名称変更

現在Branch：

```bash
git branch -m <new-name>
```

指定Branch：

```bash
git branch -m <old-name> <new-name>
```

名称変更前に新Branch名を §16.3 で検証する。

### 16.5 Branch削除

安全削除：

```bash
git branch -d <branch>
```

初期版では`-D`による強制削除を標準機能に含めない。

以下は削除不可とする。

- 現在のBranch
- Branch名未選択
- remote branch

削除前に確認を行う。

### 16.6 リモートBranch

初期版ではリモートBranchの削除、名称変更、作成を行わない。リモートBranchはSwitch候補としてのみ利用する。

---

## 17. Git Switch

### 17.1 ローカルBranch切替

```bash
git switch <branch>
```

### 17.2 リモート追跡Branch

対応するローカルBranchが存在しない場合：

```bash
git switch --track <remote>/<branch>
```

`git switch`は`-c`なしの`--track`でリモート追跡Branch名からローカルBranch名を導出する。

明示的なローカルBranch名指定が必要な場合：

```bash
git switch -c <local-branch> --track <remote>/<branch>
```

### 17.3 未コミット変更

切替によって変更が上書きされる場合、Git CLIのエラーを表示する。

初期版では以下を行わない。

- 自動stash
- 強制Switch
- `git switch --discard-changes`
- 自動Commit
- 自動Discard

### 17.4 Switch後

- 現在Branch表示を更新する
- stateを破棄し再fetchする
- 成功したBranch名を通知する

---

## 18. メニュー構成

```text
VCS
├── Status refresh
├── Update
├── Commit
├── Diff
│   ├── CLI
│   └── External
├── Log
│   ├── CLI
│   └── External
├── Discard changes
└── Git
    ├── Push
    ├── Branch
    │   ├── List
    │   ├── Create
    │   ├── Rename
    │   └── Delete
    └── Switch
```

- SVN作業コピーでは`capabilities`を参照してGit専用項目を非表示または無効化する
- 非VCSディレクトリでは、VCS操作を実行せず通知を表示する

---

## 19. キー割り当て

**【初版から変更】**

初版は`v`をプレフィックスとしていたが、Yazi既定のkeymapで`v`は`visual_mode`（選択モード）に割り当てられている（`yazi-config/preset/keymap-default.toml`）。

```toml
{ on = "v", run = "visual_mode", desc = "Enter visual mode (selection mode)" },
```

`v`始まりのchordをprependすると、Yaziが後続キーを待つため**単独の`v`が事実上使用不能になる**。§7 が「選択中の複数ファイル」を第一優先の操作対象としている以上、その選択手段を潰すことになる。

Yazi既定の`v`単独操作を潰さないことを優先し、プレフィックスは設定例ごとに明示する。標準例は`<C-g>`、READMEとユーザーマニュアルの短い例は`g`→`v`とする。プラグイン内部へキーを固定しない。

```toml
[[mgr.prepend_keymap]]
on   = [ "<C-g>", "s" ]
run  = "plugin vcs -- status"
desc = "Refresh VCS status"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "u" ]
run  = "plugin vcs -- update"
desc = "VCS update"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "c" ]
run  = "plugin vcs -- commit"
desc = "VCS commit"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "d" ]
run  = "plugin vcs -- diff"
desc = "VCS diff"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "D" ]
run  = "plugin vcs -- diff --external"
desc = "External VCS diff"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "l" ]
run  = "plugin vcs -- log"
desc = "VCS log"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "L" ]
run  = "plugin vcs -- log --external"
desc = "External VCS log"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "r" ]
run  = "plugin vcs -- discard"
desc = "Discard local changes"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "g", "p" ]
run  = "plugin vcs -- push"
desc = "Git push"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "g", "b" ]
run  = "plugin vcs -- branch"
desc = "Git branches"

[[mgr.prepend_keymap]]
on   = [ "<C-g>", "g", "s" ]
run  = "plugin vcs -- switch"
desc = "Git switch branch"
```

引数の受け取り：

```lua
entry = function(self, job)
    local action = job.args[1]        -- "status" / "diff" / ...
    local external = job.args.external -- true / nil
end
```

Yaziは位置引数と`--name` / `--name=value`形式の名前付き引数のみをサポートし、`-a`のような短縮フラグは解釈しない。

キー割り当ては設定例として提供し、プラグイン内部へ固定しない。

---

## 20. 設定仕様

```lua
require("vcs"):setup({
    detection = {
        walk_to_parent = true,
        priority = { "git", "svn" },
    },

    signs = {
        modified = "M",
        added = "A",
        deleted = "D",
        untracked = "?",
        ignored = "I",
        conflict = "C",
        missing = "!",
        replaced = "R",
        external = "X",
        locked = "L",
        property_modified = "P",
        clean = " ",
    },

    status = {
        order = 500,                    -- Entity children order。1000未満で先頭列
        aggregate_directories = true,
        ignore_externals = true,
    },

    editor = {
        command = "nvim",
        args = {},
    },

    pager = {
        command = "less",
        args = { "-R" },
    },

    update = {
        git = { "git", "pull", "--ff-only" },
        svn = { "svn", "update" },
    },

    commit = {
        allow_empty_message = false,
        git_mode = "paths",             -- "paths" | "staged"
    },

    diff = {
        git_cli = { "git", "diff", "--", "{targets}" },
        svn_cli = { "svn", "diff", "--", "{targets}" },
        git_external = nil,
        svn_external = nil,
    },

    log = {
        git_cli = {
            "git", "log", "--decorate", "--oneline", "--graph", "--", "{targets}",
        },
        git_cli_all = {
            "git", "log", "--decorate", "--oneline", "--graph", "--all",
        },
        svn_cli = { "svn", "log", "--", "{targets}" },
        git_external = nil,
        svn_external = nil,
    },

    discard = {
        confirm = true,
        recursive_confirm_text = "revert",
    },

    runner = {
        timeout_ms = 30000,             -- §21.1 参照。0で無効
    },

    git = {
        push = {
            default_remote = "origin",
            set_upstream_if_missing = true,
        },

        branch = {
            show_remote = true,
        },

        switch = {
            auto_track_remote = true,
        },
    },
})
```

初版からの差分：

- `status.cache`、`status.debounce_ms`を削除（fetcher機構が担う。§8.7）
- `status.order`を追加（§8.1）
- `commit.auto_stage_git`を`commit.git_mode`へ置換（§11.2）
- `log.git_cli_all`を追加（§13.2）
- `runner.timeout_ms`を追加（§21.1）
- 配列型の設定値は深いマージではなく、ユーザー指定値で全体を置換する
- `commit.default_scope`、`editor.wait`、`discard.include_untracked`、force／stash系の設定は安全要件または未実装のため削除

---

## 21. 外部コマンド実行

### 21.1 共通要件

- shell文字列を組み立てて実行しない
- `Command(name):arg({...})`でコマンド名と引数配列を分離する
- 標準出力を取得する（`Command.PIPED`）
- 標準エラーを取得する（`Command.PIPED`）
- 終了コードを取得する
- VCSルートまたはカレントディレクトリを`:cwd()`として実行する
- コマンドが存在しない場合、共通Runnerのspawn／実行APIが返す`Error`を捕捉し明確に通知する
- 実行中は必要に応じてローディング状態を表示する
- 非対話型のCLI処理（status、メタデータ取得、Diff、Log、Branch検証を含む）は`runner.timeout_ms`を適用する
- 認証、Update、Commitエディタ、pager、TUIなどの対話型処理はタイムアウト対象外とし、ターミナルを継承する

#### タイムアウトの実現方式

**【初版から変更】**

Yaziの`Command`にタイムアウトAPIは存在しない。`Command:output()`、`Command:status()`、`Child:wait()`のいずれもタイムアウトを受け付けない。タイムアウト機能を持つのは`Child:read_line_with { timeout = <ms> }`のみである（タイムアウト時 event=3）。

したがって`runner.timeout_ms`は以下で実装する。

1. `Command:spawn()`で`Child`を取得する
2. `Child:read_line_with { timeout = <残り時間> }`で出力を逐次読む
3. event=3（タイムアウト）が返り、かつ累計経過時間が`timeout_ms`を超えた場合、`Child:start_kill()`を呼ぶ
4. タイムアウトで終了した旨を通知する

対話型コマンド（§21.2）はタイムアウトの対象外とする。

### 21.2 対話型コマンド

認証、エディタ、pager、対話型TUI（lazygit、tig等）は、Yaziのターミナル占有機構を使用する。

```lua
local permit = ui.hide()
-- stdin/stdout/stderr を Command.INHERIT に設定して実行
permit:drop()
```

- `ui.hide()`は同時に1つしか取得できない。取得中に別の占有操作を開始しない
- 例外発生時も必ず`permit:drop()`が呼ばれるよう、`pcall`で保護する
- GUIツール（TortoiseProc等）は占有せず、終了も待たない
- 非対話型実行では`stdin`を`Command.NULL`に設定し、待ち状態にならないようにする
- Updateは認証入力の可能性があるため、対話型経路（`Command.INHERIT`）で実行する

### 21.3 ログ

デバッグ設定が有効な場合、`ya.dbg`で以下を記録する。

- 実行コマンド
- 引数
- working directory
- 終了コード
- 実行時間
- 標準エラー

認証情報、トークン、パスワードはログに出力しない。標準エラーにこれらが含まれうる場合は、既知のパターンをマスクする。

---

## 22. パス変換

**【初版から縮小】**

初版は5種類の変換スタイルを定義していたが、実際に変換が必要なのは限定的なケースのみである。

| 実行環境 | Git／SVN CLI | 外部GUIツール | 変換の要否 |
|---|---|---|---|
| Windows native Yazi | Windows版 git.exe | Windows GUI | 不要 |
| WSL上のYazi | Linux版 git | Windows GUI | **`wslpath -w`が必要** |
| Git Bash上のYazi | Windows版 git.exe | Windows GUI | 原則不要 |
| Linux | Linux版 git | 該当なし | 不要 |

要件：

- **Git／SVN CLIへ渡すパスは、常にYaziが動作する環境のネイティブ形式とする。変換しない**
- 外部GUIツールへ渡すパスのみ、必要に応じて変換する
- WSLでは`wslpath -w`、Git Bashでは`cygpath -w`を、利用可能な場合に使用する
- 変換ツールが利用できない場合は変換せずに渡し、その旨をデバッグログへ記録する

```lua
path = {
    external_style = "auto",   -- "auto" | "native" | "windows"
}
```

初版の`posix`／`wsl`は、実運用で必要となるケースが確認できないため候補から削除する。必要性が判明した時点で追加する。

---

## 23. 通知とエラー処理

### 23.1 成功通知

```text
Git push completed.
SVN update completed.
Switched to branch: feature/foo
Committed 3 files.
```

`ya.notify { title, content, timeout, level = "info" }`を使用する。

### 23.2 失敗通知

最低限以下を表示する。

- 操作名
- 終了コード
- 標準エラーの要点
- 必要に応じて実行コマンド

```text
Git switch failed.

Local changes would be overwritten.
Commit, discard, or stash the changes before switching.
```

`level = "error"`を指定する。

### 23.3 長い出力

長い標準出力／標準エラーはpagerまたは一時ファイルへ表示する。通知欄には要約のみ表示する。

---

## 24. 非同期処理

**【初版から変更】**

- status取得はfetcherにより非同期で実行される（§8.7）。プラグイン側で独自のスケジューリングを行わない
- UIスレッドをブロックしない。描画層でI/Oを行わない（§5.5）
- 同一ルートへの重複status実行の抑止はYaziのfetcherスケジューラが担う
- Update、Commit、Push、Discard、Switch中は、同一ルートへの競合操作を`ya.sync`上のフラグで抑止する
- 操作本体または対話コマンドでLuaエラーが発生しても、操作ロックと`ui.hide()`のpermitを必ず解放する。Windowsで過去にタスク保留を起こした共有`xpcall`は再導入しない
- 操作完了後に §9 の経路で表示を更新する
- 実行中にYaziが終了した場合の一時ファイル後始末は、OS標準の一時ディレクトリに置くことで最終的に回収されるものとし、明示的なクリーンアップは best-effort とする

---

## 25. 安全要件

以下を必須とする。

- Discard前の確認
- Branch削除前の確認
- 複数対象への破壊的操作時の対象一覧表示
- VCSルート外パスの拒否
- shell文字列連結の禁止（引数配列のみ）
- ユーザー入力Branch名の事前検証（`@`／`-`始まりの拒否を含む。§16.3）
- Git Force Push禁止
- Git Force Delete禁止
- 自動stash禁止
- 未追跡ファイル自動削除禁止
- 外部コマンド設定値を信頼しすぎず、実行失敗を適切に処理する
- 認証情報をログ・通知へ出力しない

**stageに関する扱い（初版から変更）**

初版の「自動stage禁止」は、§11.2 が指定するコマンドの実挙動と矛盾していた。本改訂では以下へ改める。

- 既定（`commit.git_mode = "paths"`）では、**コミット対象として明示選択され、確認画面に列挙されたパスのみ**がgitによって暗黙にstageされる
- index上のそれ以外のstage済み変更をコミットに巻き込まない
- 選択対象以外を暗黙にstageすることを禁止する
- stageが発生する旨を確認画面に明記する

---

## 26. テスト要件

### 26.1 単体テスト

最低限以下をテストする。

- Git status porcelain v2解析
  - **rename／copyレコード（`2`）が`-z`でNULフィールドを2つ消費するケース（必須。§8.4.1）**
  - untracked（`?`）、ignored（`!`）レコード
  - 日本語・空白・改行を含むパス
- SVN status XML解析（XMLエスケープ、数値文字参照を含む）
- 状態記号マッピング
- 状態優先度の適用
- ディレクトリ状態集約（ignoredの除外を含む）
- Git／SVNルート検出（`.git`がファイルの場合＝worktree／submoduleを含む）
- 対象ファイル選択（選択／hover／カレント）
- VCSルート外パスの拒否
- パス正規化
- コマンド引数構築
- Branch名検証（`@`／`-`始まりの事前拒否を含む）
- upstream有無判定
- エラー出力整形
- 設定既定値とマージ
- 配列設定の全体置換と空配列上書き
- 非対話CLIのtimeout適用対象
- Updateの認証可能な対話経路
- Luaエラー時の操作ロック／`ui.hide()` permit解放
- state破棄

### 26.2 結合テスト

一時リポジトリ／作業コピーを生成し、以下を確認する。

#### Git

clean／modified／added／deleted／renamed／untracked／ignored／conflict／commit／diff／log／discard／branch作成／branch名称変更／branch削除／switch／upstreamありPush／upstreamなしPush／detached HEAD時Push拒否

追加項目：

- **`commit.git_mode = "paths"`で未stageの選択ファイルがコミットされること**
- **`commit.git_mode = "paths"`で選択外のstage済みファイルがコミットされないこと**
- **未追跡ファイルをDiscard対象に含めた場合に除外され、通知されること**

Pushテストには`git init --bare`によるローカルbareリポジトリを使用し、外部ネットワークに依存しない。

#### SVN

clean／modified／added／deleted／missing／replaced／unversioned／ignored／property modified／conflict／update／commit／diff／log／file revert／recursive revert

SVNのupdate／commitテストには稼働リポジトリが必要である。以下で構成する。

```bash
svnadmin create <tmp>/repo
svn checkout "file://<tmp>/repo" <tmp>/wc
```

### 26.3 環境別確認

最低限以下で手動確認する。

- Windows 11＋Git Bash
- Windows 11＋WSL
- Linux
- 日本語パス
- 空白を含むパス
- 複数選択
- 大規模作業コピー
- 外部エディタ
- 外部diff
- 外部ログビューア

### 26.4 実装着手前の事前検証（新設）

本改訂の検証環境にSVN CLIが未導入であったため、以下は未確認である。実装着手前に実機で確認し、結果を本書へ反映すること。

1. `svn status --xml --no-ignore --ignore-externals`がignoredを`item="ignored"`として出力すること
2. `svn info --show-item wc-root`が対象SVNバージョンで利用可能であること
3. **SVNのサブコマンドが`--`をオプション終端として受理すること**（受理しない場合、`-`始まりパスへの`./`前置を実装する）
4. `svn revert --depth=infinity`が期待どおり再帰的に動作すること
5. `svn commit --file=<f>`がUTF-8のメッセージファイルを正しく扱うこと（特にWindows環境）
6. SVN status XMLにおけるtree-conflictの表現形式

---

## 27. 性能要件

- 1,000ファイル程度のリポジトリで、status取得によりYazi操作が長時間停止しない
- status取得中もYazi UIをブロックしない
- **`git status`には必ず`--no-optional-locks`を指定し、ユーザーが別端末で実行中のgitコマンドとindexロックが衝突しないようにする**
- **status取得はfetcherが渡す表示中ファイルのみを対象とし、リポジトリ全体を走査しない**
- ルート検出はサブプロセスを起動せず、Lua APIのみで行う（§6.2）
- 大規模SVN作業コピーでは`--ignore-externals`を既定とする

厳密な応答時間は環境依存とし、実測値をREADMEへ記載する。

---

## 28. README要件

READMEに以下を記載する。

- 概要
- 対応Yaziバージョン（`--- @since`と一致させる）
- 対応Git／SVNバージョン
- インストール方法（`ya pkg add`）
- `yazi.toml`設定（**fetcher登録は必須。省略すると状態表示が一切動作しない旨を明記**）
- `keymap.toml`設定
- `init.lua`設定
- 機能一覧
- Git／SVN差異
- ステータス記号一覧
- エディタ設定例
- pager設定例
- **外部diff設定例（`--diff-cmd`用ラッパースクリプトの実例を含む）**
- 外部ログビューア設定例
- **Commitのstage挙動（`commit.git_mode`）の説明**
- Windows／Git Bash／WSLの注意点
- 破壊的操作の注意
- 既知の制約
- トラブルシューティング
- ライセンス

---

## 29. 実装優先順位

**【初版から変更】**

初版のPhase 1はCommit（ターミナル占有＋一時ファイル＋エディタのライフサイクル）とDiscard（破壊的操作＋確認UX）を含み、MVPとして過大であった。「表示が動く」ところで一度区切る。

### Phase 1：Status MVP

- Git／SVN自動判定（§6）
- fetcher登録と`fetch`実装（§8.7）
- Git status解析（rename NULフィールドを含む。§8.4）
- SVN status XML解析（§8.5）
- `Entity:children_add`による先頭列記号表示（§8.1）
- ディレクトリ状態集約（§8.6）
- 手動status refresh（§9）
- 基本エラー通知（§23）
- 上記の単体テスト

**Phase 1完了条件**：Gitリポジトリ／SVN作業コピーでファイル一覧に状態記号が表示され、手動refreshが動作すること。

### Phase 2：共通操作

- 外部コマンド実行基盤（§21。タイムアウト含む）
- ターミナル占有機構（§21.2）
- Update
- Commit（任意エディタ、一時ファイル）
- CLI Diff（任意pager）
- CLI Log
- Discard changes（確認UX）
- 複数ファイル対応

### Phase 3：Git拡張

- Git Push
- Branch一覧／作成／名称変更／安全削除
- Git Switch
- リモート追跡Branch対応

### Phase 4：外部連携・改善

- 外部Diff（ラッパースクリプト同梱）
- 外部Log
- Windows GUIツール連携
- WSLパス変換
- 大規模リポジトリ性能改善
- テスト拡充

---

## 30. 受入条件

以下をすべて満たした場合、初期リリース（Phase 3完了時点）を受入可能とする。

1. GitリポジトリとSVN作業コピーを自動判定できる
2. Git／SVNの主要状態をファイル一覧の**先頭列**へ記号表示できる
3. ignoredを含む §8.2 の全状態を表示できる
4. renameされたファイルの状態を正しく解析・表示できる
5. ディレクトリへ配下の状態を集約表示できる
6. 選択ファイルに対してCommit、Diff、Log、Discardを実行できる
7. Gitで`git pull --ff-only`を実行できる
8. SVNで`svn update`を実行できる
9. Commitメッセージを任意エディタで編集できる
10. Commitのstage挙動が §11.2 のとおりであり、選択外のstage済み変更を巻き込まない
11. DiffとLogをCLI／pagerで確認できる
12. 外部Diff／Logコマンドを設定可能である
13. Discard前に確認が行われる
14. Discard対象から未追跡ファイルが除外される
15. Git Pushが実行できる
16. upstream未設定時にremoteを選択して設定できる
17. Git Branch一覧、作成、名称変更、安全削除ができる
18. Git Branch切替ができる
19. リモート追跡BranchからローカルBranchを作成して切替できる
20. Switch時に自動stashや強制破棄を行わない
21. Force Pushを実行しない
22. Git／SVN CLI失敗時にエラー内容を表示できる
23. 操作後にステータス表示が更新される
24. 空白および日本語を含むパスを処理できる
25. `git status`実行がユーザーの別端末でのgit操作を妨げない
26. Yazi既定のキーバインド（特に`v`）を潰さない
27. Windows 11＋Git BashおよびWSLで基本操作を確認できる
28. Updateが認証入力を要求する場合に対話経路で入力できる
29. 非対話型status／メタデータ／Diff／Log／Branch処理が`runner.timeout_ms`で終了する
30. 操作本体または対話コマンドのLuaエラー後も、同一rootの操作とYazi画面が復帰する

---

## 31. 実装方針

1. Yaziの現行プラグインAPIを公式ドキュメントと公式プラグイン実装（`yazi-rs/plugins`）から確認する
2. 公式`git.yazi`のfetcher実装とstate管理方式を参考にする
3. ただし、公式プラグインを直接改造せず、新規`vcs.yazi`として実装する
4. Yazi依存処理を §5.5 の3層に分離する
5. Git／SVN CLIの出力解析とドメインロジックはYazi APIから分離し、単体テスト可能にする
6. コマンドは文字列連結ではなく引数配列で組み立てる
7. 破壊的操作は必ず確認を行う
8. 実装と同時に単体テストを作成する
9. READMEと設定例を作成する
10. Yazi APIやCLI仕様に不明点がある場合、推測で存在しないAPIを実装しない
11. 不明点はTODOまたは制約として明示する
12. §29 のPhase順に進める
13. 各Phase完了時に以下を報告する
    - 実装した機能
    - 変更ファイル
    - 実行したテスト
    - 未解決事項
    - 手動確認手順

---

## 32. 完了時の成果物

- `vcs.yazi`プラグイン一式（フラット構成。§5.2）
- 単体テスト
- 結合テスト用fixtureまたはテストスクリプト（`svnadmin create`によるSVNリポジトリ生成を含む）
- 外部diff用ラッパースクリプト例
- README
- インストール手順
- 設定例（`yazi.toml`のfetcher登録を含む）
- キー設定例
- Git／SVN対応差異表
- 既知の制約一覧
- 動作確認結果

---

## 付録A. 検証で参照した情報源

| 項目 | 出典 |
|---|---|
| モジュール解決 | `sxyazi/yazi` `yazi-runner/src/loader/loader.rs`、`require.rs` |
| kebab-case制約 | `sxyazi/yazi` `yazi-shared/src/bytes.rs` |
| Entity子要素とorder | `sxyazi/yazi` `yazi-plugin/preset/components/entity.lua` |
| 既定keymap（`v`） | `sxyazi/yazi` `yazi-config/preset/keymap-default.toml` |
| fetcher登録形式 | `yazi-rs/plugins` `git.yazi/README.md` |
| fetch実装・state管理 | `yazi-rs/plugins` `git.yazi/main.lua` |
| Command／Child API、`ui.hide` | https://yazi-rs.github.io/docs/plugins/utils/ |
| plugin引数構文 | https://yazi-rs.github.io/docs/plugins/overview/ |
| git status出力の実挙動 | Git 2.x 実測（ignored、rename NULフィールド、`-z`とクォート） |
| `git commit -- <paths>`の挙動 | Git 2.x 実測 |
| `git restore`の未追跡ファイル挙動 | Git 2.x 実測 |
| `%09`展開 | Git 2.x 実測 |
