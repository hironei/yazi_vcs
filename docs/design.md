# vcs.yazi 設計書（as-built）

対象: `vcs.yazi/` Phase 4。

## 構成

- `main.lua`: fetcher、状態表示、status barのGit branch／SVN位置表示、status refresh、操作dispatch
- `actions.lua`: Update／Commit／CLI Diff／CLI Log／Discard、外部Diff／Logの実行フロー
- `git-actions.lua`: Push、Branch、SwitchのGit操作フロー
- `core-external.lua`: 外部環境判定、パス形式、プレースホルダー展開、設定検証
- `core-runner.lua`: 非対話runner、タイムアウト、`ui.hide()`による対話実行、GUI非占有起動
- `core-state.lua`: root別status／VCS位置情報と同一root操作ロック
- `core-vcs-info.lua`: Git branch／SVN URLの解析とstatus bar向け整形

## 外部操作フロー

```text
action + --external -> root/targets検出 -> VCS別external設定検証
       -> {root,file,targets,revision}展開
       -> WSL/Git Bashの必要時パス変換
       -> interactive: ui.hide + wait
          non-interactive: stdin/stdout/stderr切断 + spawn
```

外部コマンドもshell文字列連結を使わず、commandと引数配列を分離します。`{targets}`は対象ごとに別引数へ展開し、埋め込み形式は曖昧になるため拒否します。

## パス変換

VCS CLIはroot-relativeまたは実行環境のnative形式を使います。外部コマンドの`{root}`／`{file}`／`{targets}`に対してのみ、`path_style`または`path.external_style`に従って変換します。WSLでは`wslpath -w`、Git Bashでは`cygpath -w`をRunner経由で呼び、失敗時は元の値を保持してデバッグログへ記録します。

## 性能境界

fetcherは表示中ファイルの相対パスだけをbackendへ渡し、Git statusは`--no-optional-locks`とporcelain v2 NUL出力を使用します。全リポジトリ走査を避けることで大規模リポジトリでもYaziの表示範囲に処理を限定します。

VCS位置情報もfetcher内で取得し、描画コールバックではstateの参照だけを行います。Gitは`git branch --show-current`、SVNは`svn info --show-item url`と`repos-root-url`を使い、SVNはリポジトリルートからの相対位置（`base_url/trunk`など）へ短縮して表示します。

## 検証境界

純粋Luaテストで外部設定、プレースホルダー、環境判定、既存CLI引数を確認し、ローカルbare repositoryで既存Git操作を結合検証します。実Yazi UI、外部TUI、Windows GUI、WSL／Git Bashの実変換、SVN実CLIは手動確認が必要です。
