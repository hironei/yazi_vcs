# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 4。本文は現在の実装と要件の対応を記録し、未検証の実Yazi UI・外部GUI挙動は検証境界として分離する。

## 1. モジュール責務と依存方向

- `main.lua`: fetcher、状態表示、status bar情報、status refresh、操作dispatch
- `actions.lua`: Update／Commit／CLI Diff／CLI Log／Discard、外部操作
- `git-actions.lua`: Push、Branch、Switch
- `backend-git.lua` / `backend-svn.lua`: CLI仕様、status/info/revision出力解析
- `core-commands.lua` / `core-git.lua`: 引数構築とGit固有の純粋ロジック
- `core-context.lua`: VCS操作開始時のselected／cwd／file metadata snapshot
- `core-detector.lua` / `core-targets.lua` / `core-path.lua`: root検出、scope解決、対象選択、境界検証、パス変換
- `core-runner.lua`: 非対話CLIのタイムアウト付き実行、対話実行、GUI orphan起動
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

Actions、Git actions、Status refreshは同じresolverを使用する。Fetcherの通常status取得とstatus bar／linemodeのhover表示はこの操作scopeとは独立し、従来どおり表示中のファイルやhoverを使用できる。

未selectedのAddはcwd配下への広範囲追加となり得るため`add`確認を行う。CommitとDiscardはselected有無にかかわらずtyped confirmationを行い、cwd scopeでは絶対パスと広範囲／不可逆性を確認文へ表示する。

## 3. Fetcherと状態フロー

```text
Yazi fetcher(job.files)
  -> cwdから親方向へ.git/.svnを検出
  -> 表示中パスをroot-relativeへ変換
  -> backend.status_specをRunner.run(timeout_ms)で実行
  -> status解析、ディレクトリ集約、除外反映
  -> info_specもRunner.run(timeout_ms)で取得
  -> State.remember (ya.sync) -> ui.render
```

`State.roots[root]`は非clean状態だけを保持し、今回問い合わせたパスが出力にない場合はcleanとして既存値を削除する。描画コールバックはstate参照だけでCLIやファイルI/Oを行わない。

## 4. 設定マージ

設定テーブルはマップを再帰マージする。連続整数キーだけを持つ配列は設定単位として扱い、ユーザー指定配列で全体を置換する。したがって`update.git`、`diff.*_cli`、`log.*_cli`、`editor.args`、`pager.args`の末尾に既定値が混入しない。明示的な`false`も保持する。

## 5. 外部コマンド実行

### 5.1 非対話型

`Runner.run(spec, timeout_ms)`は`Command:spawn()`、PIPED stdout/stderr、`Child:read_line_with`で実装する。`timeout_ms > 0`ではdeadlineまで読み取り、期限到達時に`start_kill()`して`timed_out`結果を返す。`timeout_ms = 0`は無期限設定だが、API上のpollには有限の60秒窓を使い、event=3だけではkillしない。

Status、VCS info、revision、差分確認、CLI Diff/Log、Branch検証・一覧、パス変換はこの経路を使う。stdinは`Command.NULL`で、認証入力待ちを非対話タスクへ持ち込まない。`timeout_ms = 0`はタイムアウトを無効にする。

### 5.2 対話型とGUI

Update、Commitエディタ、pager、TUI外部ツール、Pushは`Runner.interactive()`を使う。`ui.hide()`取得後、command構築・status待ちを`pcall`で保護し、処理結果にかかわらずpermitをdropする。UpdateとPushは認証入力のためstdin/stdout/stderrを`Command.INHERIT`にする。

GUIは`Runner.launch()`で`ya.emit("shell", { orphan = true })`を使い、終了を待たない。外部設定はcommandと引数配列を分離し、shell文字列の組み立てはGUI起動の引用処理以外で行わない。

## 6. 操作ロックと回復

Update、Commit、Discard、Push、Branch、Switchはroot単位の`State.begin_action()`で重複を抑止する。ロック保持中の本体は`pcall`で実行し、成功・CLI失敗・Lua例外の全経路で`State.end_action()`を呼ぶ。Windowsでタスク保留を起こした共有`xpcall`は使用しない。

成功後はroot stateを破棄し、`ya.emit("refresh", {})`でfetcher経路を再実行する。CLI失敗は成功扱いにせず、終了コードとstderr要約を通知する。

## 7. 対話操作の個別仕様

- Update: 設定配列を展開して`Runner.interactive`で実行。成功後にrefresh、失敗時は通知。
- Commit: 一時メッセージファイルを作成し、エディタ終了後に内容を確認。Git `paths`モードは選択パスだけを暗黙stageする。
- Diff/Log: CLI出力をタイムアウト付きRunnerで収集し、一時ファイルをpager/editorで表示。
- Discard: tracked対象だけを確認入力後に復元。未追跡／ignoredは除外。
- Push/Branch/Switch: Git専用Runner経路を使い、force操作・auto-stash・強制switchは行わない。

## 8. セキュリティと互換性

- VCS root外の対象を拒否する
- CLI引数は配列で渡し、ユーザー入力Branch名は事前検証する
- Force Push、Force Delete、auto-stash、未追跡ファイル削除を実行しない
- 認証情報をログ・通知へ出力しない
- 配列設定の置換により、ユーザーの明示したコマンド引数を既定値が変形しない
- 対応Yaziは26.5.6以降。`main.lua`の`--- @since 26.5.6`とREADMEを一致させる

## 9. 要件・テスト対応

| 要件領域 | 実装 | 主な検証 |
| --- | --- | --- |
| VCS検出／status | `core-detector.lua`, `backend-*`, `main.lua` | backend/detector/status tests、Git/SVN統合 |
| Scope／対象境界／引数 | `core-context.lua`, `core-targets.lua`, `core-path.lua`, `core-commands.lua` | scope/target/command tests |
| 設定マージ | `config.lua` | false、配列置換、空配列テスト |
| timeout | `core-runner.lua` と全read-only caller | `next_poll`、構文、実Yazi手動確認 |
| Update／認証 | `actions.lua`, `core-runner.lua` | 実Yazi・認証環境で手動確認 |
| ロック／permit回復 | `actions.lua`, `git-actions.lua`, `core-runner.lua` | Lua例外注入を含む実Yazi確認 |
| 外部Diff／Log | `core-external.lua`, `actions.lua` | placeholder/environment tests、外部GUI手動確認 |

## 10. 検証境界

WindowsネイティブLuaでは純粋テスト、Git bare repository、SVN working copy統合を実行する。実Yazi画面、認証入力、外部TUI、Windows GUI、WSL/Git Bashの実変換は別途手動確認とし、自動テスト成功と混同しない。
