# TODO

## 目視確認（ユーザー対応が必要）

- [ ] 実際のYazi画面でPhase2〜4のキー操作と通知を確認する
- [ ] Git認証が必要なPushをWindows 11のGit Bash／WSLで確認する
- [ ] Git Branch入力UIとpager表示を実Yaziで確認する
- [ ] 外部Diff／LogのTUIとWindows GUI起動を実環境で確認する
- [ ] `git.yazi`との同時利用で記号が二重表示されないか確認する
- [ ] WSLの`wslpath -w`、Git Bashの`cygpath -w`によるGUIパス変換を確認する

## Phase 4：外部連携・改善

- [x] 外部Diff（`--diff-cmd`ラッパーを含む）
- [x] 外部Log
- [x] Windows GUIツール連携
- [x] WSL／Git Bashパス変換経路
- [x] 大規模リポジトリ向けstatus範囲・index lock配慮
- [x] 外部設定・環境判定テスト拡充

## 未検証事項

- [ ] SVNの`external`／`obstructed`／`incomplete`状態を実作業コピーで再現する
- [ ] SVN update／commit／revertのWindows実CLI確認
- [ ] 外部GUIの実起動と終了待ちなし動作
