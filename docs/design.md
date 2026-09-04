# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 4、および Issue #38（Yazi 26.8.15対応: fetcher API更新とYazi依存の互換レイヤ分離）。本文は現在の実装と要件の対応を記録し、未検証の実Yazi UI・外部GUI挙動は検証境界として分離する。

## 1. モジュール責務と依存方向

- `main.lua`: fetcher（`core-fetcher.lua`への委譲を含む）、状態表示、status bar情報、status refresh、操作dispatch
- `core-fetcher.lua`: **【新設、Issue #38】** Yazi `UnstableFetcher`契約（`ya.co()`／`coroutine.yield(file, {retry=..., error=...})`）のみを集約するアダプタ。`main.lua`やbackendへYazi固有のfetcher result形式を漏らさない（§3参照）
- `actions.lua`: Update／Commit／CLI Diff／CLI Log／Discard、外部操作
- `git-actions.lua`: Push、Branch、Switch
- `backend-git.lua` / `backend-svn.lua`: CLI仕様、status/info/revision出力解析
- `core-commands.lua` / `core-git.lua`: 引数構築とGit固有の純粋ロジック
- `core-context.lua`: VCS操作開始時のselected／cwd／file metadata snapshot。Yazi 26.8.15で`tab.selected`の`pairs()`要素が`Url`から`File`へ変わるため、`.url`フィールドの有無で分岐する軽量なduck-typingで両形式を吸収する（§2、要件§7.3）
- `core-scope.lua`: context snapshotからの共通scope解決と失敗通知
- `core-detector.lua` / `core-targets.lua` / `core-path.lua`: root検出、scope解決、対象選択、境界検証、パス変換
- `core-runner.lua`: 非対話CLIのタイムアウト付き実行、対話実行、GUI orphan起動。Issue #38では変更しない（要件§8.7.2）
- `core-state.lua`: `ya.sync`越しのroot別status/infoと操作ロック
- `core-external.lua` / `core-vcs-info.lua` / `core-notify.lua`: 外部設定、表示整形、通知
- `config.lua`: 既定値とユーザー設定のマージ

純粋Luaで実行できる解析・引数・設定ロジックをYazi APIから分離し、`tests/`から直接検証する。Yazi依存処理は`main.lua`、actions、state、runnerの境界に閉じ込める。

## 2. 操作コンテキストとScopeフロー

```text
Context Snapshot (selected / cwd / file metadata)
  -> Scope Resolution (selected | cwd, explicit)
  -> Repository Resolution (root / kind / same-repository check)
  -> Path-level or Repository-level operation
  -> Risk Policy (read-only / mutating / destructive)
  -> Command Execution
```

`core-context.lua`は1回の操作でYazi contextを1回だけ取得する。`core-targets.lua`はhoveredを参照せず、selectedがあれば全selected、なければcwdを返す。各selected pathはdirectoryなら自身、fileならparentをDetectorへ渡し、全pathのkind/root一致を検証する。異なるrepository、Git/SVN混在、VCS外path混在は拒否する。root-relative `.` はrepository scopeとして扱い、Diff／Logではpath filterを省略する。

**【Yazi 26.8.15対応で変更、Issue #38】** `tab.selected`の`pairs()`が返す各要素は、26.5.6では`Url`、26.8.15では`File`である。`core-context.lua`は`local url = entry.url or entry`のように`.url`フィールドの有無で分岐し、いずれの形式からも同一のpathへ解決する。バージョン判定用の複雑な分岐は追加しない。`File`が持つ`cha.is_dir`等の付随情報は、必要に応じて既存のfile/directory metadata snapshotへそのまま反映する。

Actions、Git actions、Status refreshは同じresolverを使用する。Fetcherの通常status取得とstatus bar／linemodeのhover表示はこの操作scopeとは独立し、従来どおり表示中のファイルやhoverを使用できる。

未selectedのAddはcwd配下への広範囲追加となり得るため`add`確認を行う。CommitとDiscardはselected有無にかかわらずtyped confirmationを行い、cwd scopeでは絶対パスと広範囲／不可逆性を確認文へ表示する。

## 3. Fetcherと状態フロー

**【Yazi 26.8.15対応で全面変更、Issue #38】** Yazi 26.8.15のfetcher契約変更（yazi#4234, yazi#4235）に伴い、`M:fetch`の戻り値契約とVCS status取得ロジックを分離する。4段階のパイプラインとする。

```text
main.lua: M:fetch(job)
  1. 呼び出し口 (main.lua)。job.files が空なら core-fetcher.lua の Fetcher.noop(job) へ即委譲
  2. VCS status refresh (main.lua内、既存ロジックを踏襲)
       -> cwdから親方向へ.git/.svnを検出（Detector）
          検出できない -> State.forget(cwd) を呼んだ上で Fetcher.noop(job) へ
       -> 表示中パスをroot-relativeへ変換し、重複排除した問い合わせリストを構築
       -> backend.status_specをRunner.run(timeout_ms)で1回だけ実行
          失敗 -> Fetcher.error(job, err) へ（State更新は行わない）
       -> status解析、ディレクトリ集約、除外反映
       -> info_specもRunner.run(timeout_ms)で取得
  3. State更新 (core-state.lua)
       -> State.remember (ya.sync) -> ui.render
  4. Fetcher result生成 (core-fetcher.lua)
       -> Fetcher.retry(job) が job.files 全件へ coroutine.yield(file, {retry=true}) する
```

- ステップ2・3はYazi fetcher契約に依存しない既存の同期的処理（`Detector`、`BACKENDS[kind]`、`Runner.run`、`State.remember`）をそのまま踏襲し、`main.lua`内に留める。新規モジュール化は行わない（Issue #38は「Yazi fetcher契約からの独立」を要求しているのであって、ファイル分割そのものを要求していない）
- `core-fetcher.lua`が提供するのはステップ1（`job.files`空時の即時委譲）とステップ4（result coroutine生成）の2箇所の呼び出し先、すなわち`Fetcher.noop`／`Fetcher.error`／`Fetcher.retry`の3関数のみ。coroutine／`ya.co`の実体はすべてこのモジュール内に閉じる。

```lua
-- core-fetcher.lua
local M = {}

-- 正常取得時のみ使用。VCS statusは外部操作でも変化しうるため、常に再取得可能とする。
function M.retry(job)
    return ya.co(function()
        for _, file in ipairs(job.files) do
            coroutine.yield(file, { retry = true })
        end
    end)
end

-- VCS対象外（リポジトリ未検出）時に使用。公式git.yaziの26.8.15対応実装がYazi組み込みの
-- noopフェッチャー（yazi-plugin/preset/plugins/noop.lua）へ委譲する挙動と同じく、
-- retryキーなしの{}をyieldする（要件§8.7.2、付録A）。
function M.noop(job)
    return ya.co(function()
        for _, file in ipairs(job.files) do
            coroutine.yield(file, {})
        end
    end)
end

-- Runner実行等のエラー時に使用。公式git.yaziがCommand:spawn()失敗時にya.err()でログした
-- うえでnoopへ委譲するのと同じく、ya.err()でログしてから retry なしで終了する。
function M.error(job, err)
    ya.err(tostring(err))
    return M.noop(job)
end

return M
```

- `main.lua`の`M:fetch(job)`は、ステップ2・3を実行する既存ロジック（現行の`fetch_vcs_info`と同様の非公開ローカル関数、例: `refresh_vcs_status(job)`）を引き続き保持する。新契約で薄くなるのは最終的な戻り値の生成部分だけであり、`refresh_vcs_status`の結果（成功／VCS対象外／エラー）に応じて`Fetcher.noop`／`Fetcher.error`／`Fetcher.retry`のいずれかへ委譲する（要件§8.7.2の`main.lua`側サンプル）。Detector呼び出しやRunner実行そのものが軽量化されるわけではない
- `coroutine.yield`は`refresh_vcs_status`が内部で使った重複排除後の問い合わせリストではなく、`job.files`原本の全件に対して行う（`Fetcher.retry`/`Fetcher.error`の実装がこれを保証する。要件§8.7.2）
- `State.forget(cwd_str)`（VCS対象外検出時にルート追跡を破棄する副作用）は、ステップ2の中で`Fetcher.noop`を呼ぶ**前**に必ず実行する。`core-fetcher.lua`側にこの副作用を持たせない
- `State.roots[root]`は非clean状態だけを保持し、今回問い合わせたパスが出力にない場合はcleanとして既存値を削除する。描画コールバックはstate参照だけでCLIやファイルI/Oを行わない
- 正常系は毎回`Fetcher.retry`（`{retry=true}`）を返すため、Yaziは同一ファイル群に対して継続的に`fetch`を再実行し得る。§8性能要件を満たす範囲に収まることを実機で確認する（要件§26.5）

## 4. 設定マージ

設定テーブルはマップを再帰マージする。連続整数キーだけを持つ配列は設定単位として扱い、ユーザー指定配列で全体を置換する。したがって`update.git`、`diff.*_cli`、`log.*_cli`、`editor.args`、`pager.args`の末尾に既定値が混入しない。明示的な`false`も保持する。

## 5. 外部コマンド実行

### 5.1 非対話型

`Runner.run(spec, timeout_ms)`は`Command:spawn()`、PIPED stdout/stderr、`Child:read_line_with`で実装する。`timeout_ms > 0`ではdeadlineまで読み取り、期限到達時に`start_kill()`して`timed_out`結果を返す。`timeout_ms = 0`は無期限設定だが、API上のpollには有限の60秒窓を使い、event=3だけではkillしない。

Status、VCS info、revision、差分確認、CLI Diff/Log、Branch検証・一覧、パス変換はこの経路を使う。stdinは`Command.NULL`で、認証入力待ちを非対話タスクへ持ち込まない。`timeout_ms = 0`はタイムアウトを無効にする。

### 5.2 対話型とGUI

Update、ネイティブCommit、pager、TUI外部ツール、Pushは`Runner.interactive()`を使う。`ui.hide()`取得後、command構築・status待ちを`pcall`で保護し、処理結果にかかわらずpermitをdropする。Update、Commit、Pushは認証またはeditor入力のためstdin/stdout/stderrを`Command.INHERIT`にする。

GUIは`Runner.launch()`で`ya.emit("shell", { orphan = true })`を使い、終了を待たない。外部設定はcommandと引数配列を分離し、shell文字列の組み立てはGUI起動の引用処理以外で行わない。

## 6. 操作ロックと回復

Update、Commit、Discard、Push、Branch、Switchはroot単位の`State.begin_action()`で重複を抑止する。ロック保持中の本体は`pcall`で実行し、成功・CLI失敗・Lua例外の全経路で`State.end_action()`を呼ぶ。Windowsでタスク保留を起こした共有`xpcall`は使用しない。

成功後はroot stateを破棄し、`ya.emit("refresh", {})`でfetcher経路を再実行する。CLI失敗は成功扱いにせず、終了コードとstderr要約を通知する。

## 7. 対話操作の個別仕様

- Update: 設定配列を展開して`Runner.interactive`で実行。成功後にrefresh、失敗時は通知。
- Commit: typed confirmation後、Git/SVNのネイティブcommit commandをinteractiveに起動する。Git `paths`モードは選択パスだけを暗黙stageし、Git/SVNが標準editor解決とcommit message templateを管理する。
- Diff/Log: CLI出力をタイムアウト付きRunnerで収集し、一時ファイルをpager/editorで表示。
- Discard: tracked対象だけを確認入力後に復元。未追跡／ignoredは除外。
- Push/Branch/Switch: Git専用Runner経路を使い、force操作・auto-stash・強制switchは行わない。

## 8. セキュリティと互換性

- VCS root外の対象を拒否する
- CLI引数は配列で渡し、ユーザー入力Branch名は事前検証する
- Force Push、Force Delete、auto-stash、未追跡ファイル削除を実行しない
- 認証情報をログ・通知へ出力しない
- 配列設定の置換により、ユーザーの明示したコマンド引数を既定値が変形しない
- 対応Yaziは26.8.15以降（**【Yazi 26.8.15対応で変更、Issue #38】** fetcher契約の破壊的変更により26.5.6とは非互換）。`main.lua`の`--- @since 26.8.15`とREADMEを一致させる

## 9. 要件・テスト対応

| 要件領域 | 実装 | 主な検証 |
| --- | --- | --- |
| VCS検出／status | `core-detector.lua`, `backend-*`, `main.lua` | backend/detector/status tests、Git/SVN統合 |
| fetcher契約（Yazi 26.8.15） | `core-fetcher.lua`, `main.lua` | fetcher adapter単体テスト、実Yazi 26.8.15確認（要件§26.5） |
| selected表現差異（Yazi 26.8.15） | `core-context.lua` | File／Url双方のcontext snapshotテスト |
| Scope／対象境界／引数 | `core-context.lua`, `core-scope.lua`, `core-targets.lua`, `core-path.lua`, `core-commands.lua` | scope/target/command tests |
| 設定マージ | `config.lua` | false、配列置換、空配列テスト |
| timeout | `core-runner.lua` と全read-only caller | `next_poll`、構文、実Yazi手動確認 |
| Update／認証 | `actions.lua`, `core-runner.lua` | 実Yazi・認証環境で手動確認 |
| ロック／permit回復 | `actions.lua`, `git-actions.lua`, `core-runner.lua` | Lua例外注入を含む実Yazi確認 |
| 外部Diff／Log | `core-external.lua`, `actions.lua` | placeholder/environment tests、外部GUI手動確認 |

## 10. 検証境界

WindowsネイティブLuaでは純粋テスト、Git bare repository、SVN working copy統合を実行する。実Yazi画面、認証入力、外部TUI、Windows GUI、WSL/Git Bashの実変換は別途手動確認とし、自動テスト成功と混同しない。

## Issue #42: VCS Changes View

The Changes action resolves the repository through the existing `core-scope` / `core-targets` semantics, then runs one repository-wide backend status query. `core-changes.lua` filters clean, ignored, and bookkeeping-only entries and returns a stable path-ordered list. The same backend parser is used by the fetcher and the Changes action.

The action creates a Yazi Search URL with `Url(root):into_search("VCS Changes")`, emits the standard `cd` and `update_files` events, and constructs `File` entries from changed paths. Existing metadata is obtained with `fs.cha`; deleted or missing paths use synthetic regular-file `Cha` metadata so they remain visible and selectable.

`core-context.lua` treats `url.path` as the physical path for both regular and Search URLs and records whether the current context is a Search View. `core-scope.lua` passes that flag into target resolution; an empty Search View selection returns `no-target` and cannot fall back to cwd. Add, Commit, and Discard therefore reuse their existing confirmation and safety policies while operating on selected physical paths only.

For Git Diff, selected untracked paths are compared with a shared empty temporary file through `git diff --no-index`. Exit code 1 is accepted as the expected "differences found" result. Git Log filters untracked selections and reports that they have no history. SVN uses the shared changed-path and selection flow without applying Git-specific no-index behavior.

## Feature Addendum: Temporary Hovered-File VCS Log Notification

The feature adds the functional `log-preview` action to the existing `vcs`
module. The action resolves the current hovered item through a `ya.sync`
closure, runs the bounded read-only Git or SVN log command, and displays the
result through the standard `ya.notify` API. It has no custom Previewer layout,
per-tab toggle state, or hover polling loop.

The log domain logic belongs in `core-log-preview.lua`. It owns Git and SVN
argument construction with a fixed limit of five entries, Git tab-separated
output parsing, SVN XML log-entry parsing, entity decoding, first-message-line
selection, and one-line formatting.

The action adapter resolves the hovered URL to a repository detector start
directory (the file's parent for regular files and the item itself for
directories), calls the existing `Detector.detect`, converts the item to a
root-relative path with `Path.strip_prefix`, and executes the read-only command
with `Runner.run`. It uses the same timeout and command argument boundaries as
the existing VCS operations.

`core-notify.lua` keeps the normal single-line notification helpers and adds a
bounded multi-line history notification with an eight-second timeout. Log
entries are joined with line breaks after parsing, while command error details
are collapsed to one line before display. The notification explains missing
repositories, untracked items, empty history, and command failures.

The `peek` and `seek` methods remain as compatibility pass-throughs for users
who still have the former catch-all `url = "*"`, `run = "vcs"` previewer rule.
They delegate to the standard Yazi preview adapter without modifying the job's
area. New installations do not need a custom previewer rule for VCS logs.

Traceability: requirements 1-2 map to `actions.lua` and `core-log-preview.lua`;
requirement 3 maps to `core-notify.lua` and the shared runner; requirement 4
maps to the pass-through preview methods and unchanged existing actions. Tests
cover the fixed log limit, Git/SVN parsing and integration, message handling,
temporary notification formatting, and standard preview classification.

## Issue #47 Design: Temporary VCS Log Spot

`actions.lua` keeps `log-preview` unchanged and adds `log-spot`. The new action
captures the same hovered-item context, clears any stale VCS Spot state, and
calls Yazi 26.8.15's experimental dynamic Spotter API for both URL classes:

```lua
local file_spotter = rt.plugin.spotters:insert(1, { url = "*", run = "vcs" })
local directory_spotter = rt.plugin.spotters:insert(1, { url = "*/", run = "vcs" })
```

The returned `id.value` values are stored in `core-state.lua` together with a
VCS Spot active flag, then `ya.emit("spot", { force = true })` starts the
display. The registrations remain while the VCS Spot is active, allowing
Yazi's standard `swipe` action to invoke `vcs:spot(job)` again for a new hover
target. Registration failures are reported through the existing single-line
notification helper, and any successfully registered sibling is removed when
the other registration fails.

`main.lua` implements `M:spot(job)`, which retains the temporary IDs while VCS
Spot is active and removes stale IDs when the active flag is false. It builds rows from
`core-log-preview.lua` and passes a styled `ui.Table` to `ya.spot_table`. The
table has fixed `Date` and `Revision` columns and a fill `Message` column;
errors are represented by one fallback row. The IDs are removed by the Tab transition and
close handlers before standard Spot or close is emitted. This lets repeated
swipe operations keep using the VCS handler without permanently changing the
standard Spotter configuration.

The optional `[spot]` Tab binding invokes `spot-tab`. The action removes the
temporary IDs and forces another Spot selection when the VCS flag is true. When
the flag is false, it emits the manager `escape` action, preserving normal
Spot close behavior. The `spot-close` action performs the same cleanup before
handling Esc/C-[ / C-c. This keeps the feature temporary without interrupting
the standard `h`/`l` swipe behavior.

The dynamic-API calls are localized to `actions.lua` and `main.lua` so the
Yazi-version-specific surface can be replaced if the experimental API changes.
Tests cover the table row transformation; live acceptance must additionally
verify the Yazi 26.8.15 Spot UI, Tab transition, and cancellation cleanup.

## Issue #52 Design: Selectable VCS Log Field Copy

`core-log-preview.lua` parses each Git/SVN entry into separate Date, Revision,
and Message fields. The existing notification path uses a compatibility
formatter, while `main.lua` renders all three fields in the Spot table and
keeps the default `c c` cell-copy action on Message.

The plugin stores the rendered entries and a one-based selected-row index in
the shared state. Because a functional plugin action receives no Spot row
index, the documented `[spot]` `j`/`k`/Up/Down bindings first invoke Yazi's
standard arrow action and then update the plugin index. `spot-copy-revision`
and `spot-copy-message` read the selected entry and copy only that field with
`ya.clipboard`; they report a bounded warning when no VCS row is available.
These tracking actions no-op outside VCS Log Spot, preserving normal Spot
behavior. No changes are made to the standard `h`/`l` swipe, Tab transition,
close cleanup, or normal Spotter registrations.

## Issue #50 Design: VCS Log Spot Swipe Follow

The dynamic file and directory Spotters remain registered while the shared VCS
Spot-active flag is true. Yazi's existing `[spot]` `swipe -1` and `swipe 1`
actions then move the hovered item and reselect the same VCS Spot handler,
which reruns `M:spot(job)` with the new file or directory. No custom h/l
movement implementation is needed, so standard Spot swipe semantics remain the
source of truth.

`spot-tab` and the new `spot-close` action call the shared cleanup path before
emitting standard Spot or escape. The cleanup clears both dynamic Spotter IDs
and the active flag. The close bindings are documented for Esc, C-[, and C-c;
when the flag is false, the existing Tab bridge still emits the normal close
action. `M:spot(job)` only removes stale IDs when the active flag is already
false, preventing a valid swipe-triggered VCS render from losing its matcher.

## Issue #54 Design: Native VCS Commit Editor Flow

The commit action keeps its existing scope resolver, typed confirmation, root
lock, and post-operation refresh behavior. After confirmation it builds only
the native VCS command arguments and invokes `Runner.interactive()` with the
repository root as `cwd`:

```text
Commit
  |
  +-- Git / paths mode  -> git commit -- <targets>
  +-- Git / staged mode -> git commit
  +-- SVN               -> svn commit -- <targets>
```

No `--file`, `--editor`, `--editor-cmd`, `--status`, or `-v` option is added by
the plugin. Git and SVN therefore resolve the user's configured editor and
generate their own commit-message template, including the changed-file list
and any configured template, status, verbose, or hook behavior. The existing
`editor` setting remains available for CLI Diff/Log display fallback only.

The native command owns editor cancellation, empty-message handling, hooks,
and commit errors. On any command failure, `actions.lua` clears the cached
root state and emits a refresh before reporting the VCS error. This is needed
because Git path-mode commit may update the index before the editor returns.
Successful commits use the existing interactive completion path, which also
clears state and refreshes status. No commit-message temporary file is created
by the plugin.

`core-commands.lua` is the pure seam for the three argument shapes, and its
unit tests assert that message-file arguments are absent. The Git integration
test configures a temporary repository-local editor, verifies that the native
commit template contains the status heading and selected path, and confirms
that a staged path outside the selection remains staged. Live Yazi terminal,
Git editor, and SVN editor acceptance remain environment-dependent manual
checks.
