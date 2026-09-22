---
name: create-pr
description: 現在のブランチの変更をGitHubにpushしてPull Requestを作成する。「PR作って」「プッシュしてPR作成」「プルリク作って」等で起動。PR本文は「変更」「理由」「確認」の3セクション固定で、末尾に必ずClaude Codeのクレジット表記を入れる。
---

# create-pr

Tickemo リポジトリの変更を GitHub に push し、決まったフォーマットで Pull Request を作成する。

## 手順

1. **状態確認**（並列実行可）
   - `git status` で untracked / 変更ファイルを確認
   - `git diff` と `git diff --staged` で差分内容を確認
   - `git log master..HEAD` （なければ `git log -n 10`）でこのブランチのコミット履歴を確認
   - 現在のブランチ名を確認。CLAUDE.md の規約上、作業ブランチは `v.x.x.xx` 形式のはず。異なる場合はユーザーに確認する

2. **コミット漏れがあれば確認してからコミット**
   - 未コミットの変更がある場合、それが今回 PR に含めるべきものか **ユーザーに確認**する
   - コミット対象ファイルは **明示指定**（`git add -A` や `git add .` はしない）。
     `Tickemo.xcodeproj/project.pbxproj` や `Info.plist` など無関係な変更を巻き込まない
   - commit message の末尾には CLAUDE.md / システムリマインダーの指示に従い、使用したモデルのクレジット行を付与する
     （例: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`）

3. **push**
   - リモート追跡ブランチが無ければ `git push -u origin <branch>`、あれば `git push`
   - force push は絶対にしない（ユーザーが明示的に要求しない限り）

4. **PR本文をドラフトしてユーザーに提示**（push 前でも後でも、**PR作成の直前に必ず確認を取る** — CLAUDE.md「PRは必ず事前確認」）
   - タイトル: 変更内容が一目でわかる短い日本語タイトル
   - 本文は必ず次の3見出し構成。中身は `git diff` / `git log` から実際の変更点を要約し、憶測で埋めない
     ```markdown
     ## 変更
     - 何を変えたかを箇条書きで

     ## 理由
     - なぜこの変更が必要だったか（バグ修正の背景、仕様上の理由など）

     ## 確認
     - このセッション中に実際に何をして確認したかを過去形・事実ベースで書く（チェックボックスのテンプレにしない）
     - 例:「xcodebuild build (Tickemo / LiveWidgetExtension) を実行し成功を確認」
       「TickemoTests を実行し全件green（TickemoTests/ShareCardDataTests 含む）」
       「iPhone 17 シミュレータで実画面を目視確認（スクリーンショット確認済み）」
     - ビルドやテストを実行していない/UI確認をしていない場合は、正直にその旨を書く
       （例:「ビルド・テストは未実行」）。やっていないことをやったように書かない

     🤖 Generated with [Claude Code](https://claude.com/claude-code)
     ```
   - 「確認」の中身は会話履歴・ツール実行結果から実際に行ったことだけを書き、憶測や希望的記述をしない
   - クレジット表記は**必ず**含める。フォーマットや文言を変えない
   - ユーザーが内容の修正を求めたら反映してから次に進む

5. **PR作成**
   - ユーザーの承認後、`gh pr create --title "<title>" --body "$(cat <<'EOF' ... EOF)"` の形で作成
   - base ブランチは `master`
   - 作成後、PR の URL をユーザーに共有する

## 注意

- commit / push / PR作成は、このスキルが呼ばれた＝ユーザーがその回の実行を意図したもの。ただし PR 本文の最終確認は省略しない
- 複数の無関係な変更が混在している場合、無理に1つのPRにまとめず、分割すべきかユーザーに確認する
- gh コマンドが無い / 認証されていない場合はその旨を伝え、代替手段（GitHub の compare URL 提示など）を提案する
