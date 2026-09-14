# Tickemo（native / Swift）作業ガイド

Tickemo iOS アプリ本体。SwiftUI + Core Data(`NSPersistentCloudKitContainer`) + MusicKit + RevenueCat。
旧 React Native 実装からの完全移行版（移行元は別リポジトリで管理、本リポジトリはSwift専用）。

---

## 1. ビルド・テスト・検証

Simulator: **iPhone 17** — `id=C6D4BDF4-D259-48E4-8D30-5D4627E8CF65`
（存在しない場合は `xcrun simctl list devices available | grep iPhone` で別の起動中デバイスを使う）

# ビルド（両スキーム）
xcodebuild build -scheme Tickemo             -destination 'id=C6D4BDF4-D259-48E4-8D30-5D4627E8CF65'
xcodebuild build -scheme LiveWidgetExtension -destination 'id=C6D4BDF4-D259-48E4-8D30-5D4627E8CF65'

# テスト
xcodebuild test -scheme Tickemo -destination 'id=C6D4BDF4-D259-48E4-8D30-5D4627E8CF65' -only-testing:TickemoTests
# 個別: -only-testing:TickemoTests/ShareCardDataTests
```

### 新規 .swift ファイルは Xcode プロジェクトへの登録が必須

GUI が無いので `scripts/register_*.rb` のパターンで登録スクリプトを1本書いて実行:

```bash
GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec \
ruby -I/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec/gems/xcodeproj-1.27.0/lib \
  scripts/register_<feature>.rb
```

- アプリ本体のファイルは `Tickemo` ターゲット、テストは **`TickemoTests` ターゲットにも**追加する
- 既存スクリプト（例 `register_share_feature.rb`）をテンプレにする

### UI 変更の目視確認

タップ自動化ツールが無い。次のどちらかで確認する:

1. **View を PNG に落とす**（推奨・軽量）: `TickemoTests` に一時テストを足し、
   `ShareCapture.capturePNG(...)` 等でレンダリングして `/tmp/foo.png` に書き出し、
   その画像を読む。確認後テストは削除。
2. **画面に到達して screenshot**: `AppDelegate.swift` に DEBUG 限定の seed（サンプル
   Core Data レコード投入、`ProcessInfo.processInfo.environment["TICKEMO_SEED_X"]`）と
   `ContentView.swift` に route（`TICKEMO_SHOW_X`）の足場を一時的に入れ、
   `xcrun simctl install` → `SIMCTL_CHILD_<VAR>=1 xcrun simctl launch` →
   `xcrun simctl io <udid> screenshot`。**足場は commit 前に `git checkout -- <file>` で戻す**
   （本番画面は戻さない、routing/seed の足場だけ）。

過去にこの目視確認で、locale 依存の日付表示・コントラスト不足のプレースホルダ色・
computed property からの Core Data 二重 insert などユニットテストが見逃すバグを検出している。

### 「完了」の定義

両スキームのビルド成功 + `TickemoTests` グリーン + UI 変更は目視確認済み + 一時足場を revert 済み。

---

## 2. 既知の落とし穴 / 恒常的な失敗

- **`NextLiveCardDataTests`** の `testInstantDefaultsToEighteenHundredWhenStartTimeAbsent` /
  `testIsPastUsesFullInstantNotDateOnly` は master でも失敗する。追いかけない
- **`DuplicateRecordSweeperTests`** はテストクラス横断の実行順による共有状態で稀に落ちる。
  単独実行なら通る
- `ImageRenderer.scale` は `1` 固定（デバイス scale での拡大を防ぐ）
- シェアカードは固定キャンバス: Ticket / CD `1480x1200`、Receipt `826x2044`。
  レイアウトは絶対 offset + `.clipped()` で組まれており、可変長テキストは
  `minimumScaleFactor` + 高さ制約が両方無いと縮まない

---

## 3. コーディング規約

- **日付・時刻**: `Calendar.current` や locale 未固定の `DateFormatter` は**禁止**。
  必ず `DateFormatting`（`timeZone = UTC` 固定、`utcCalendar`、`date(from:)` 等）を使う。
  これは実バグとして何度も踏んでいる
- **ユーザー向け文字列・エラーメッセージは日本語**
- **純粋ロジックとビューを分離**: テスト可能なロジックは `Support/` に
  `enum + static func`（`ShareCardData`, `ArtistGrouping`, `SetlistPerformers`, `StatisticsData` …）、
  SwiftUI View はそれを consume するだけ。ロジックには `TickemoTests` に単体テストを書く
- **RN パリティ**: 移植時は挙動を削らず完全再現する方向で判断する。
  RN と意図的に変えた箇所は「なぜ変えたか」をコメントに残すこと（既存コードのスタイルに合わせる）
- 移植元の対応（目安、旧RNリポジトリ参照）:
  `screens/X.tsx` → `Screens/XView.swift` / `components/X.tsx` → `Components/XView.swift` /
  純ロジック → `Support/`

---

## 4. アーキテクチャの要点

- **Core Data エンティティは `CD_` プレフィックス**: `CD_ChekiRecord`（ライブ記録）、
  `CD_SetlistItem`（セトリの1行 song/encore/mc）、`CD_UserProfile`（単一レコード）。
  `NSPersistentCloudKitContainer` で private DB 同期。`Persistence/`
- **`Migration/`**: 旧 RN の iCloud JSON ブロブ（`react-native-cloud-storage` 由来）からの
  初回起動時移行。重複排除の鍵は `record.id`(UUID)。データを失わないことが最優先制約
- **セトリの「誰が」は2種類あるので注意**（混同しない）:
  - `CD_SetlistItem.artistName` = 音源のアーティスト（Apple Music 検索由来。カバー曲は**原曲側**）
  - `CD_SetlistItem.performerName` = その公演で実際に演奏した出演者
  - 「実際に歌った人」を出すときは必ず `SetlistPerformers.displayName(performer:songArtist:)` を通す
- **課金**: RevenueCat。premium の呼称は **"Plus"**。`PurchasesService.shared.isPremium`
- **MusicKit**: `AppleMusicService`（旧 `modules/*/ios/*.swift` から Expo ラッパーを剥がして移植）
- ウィジェット: `LiveWidgetExtension`、App Group `group.com.anonymous.Tickemo.widget` の
  `UserDefaults` 経由でデータ受け渡し

---

## 5. ドメイン用語

| 語 | 意味 |
|---|---|
| チェキ記録 / record | 1公演ぶんのライブ記録（`CD_ChekiRecord`）。UI 上は「チケット」 |
| セトリ | セットリスト。曲 / アンコール区切り / MC の並び（`CD_SetlistItem`） |
| ワンマン / 対バン / フェス | 単独公演 / 複数出演者の公演 / フェス。`liveType` |
| performer / 出演者 | その公演で実際に演奏した人。source artist（音源アーティスト）と別物 |
| カバー曲 | 他アーティストの曲を演奏。`artistName` は原曲、`performerName` は演奏者 |
| Plus | 課金プラン。Receipt / CD シェアカードなどが Plus 限定 |
| シェアカード | 記録を画像化して共有する機能。Ticket / CD / Receipt の3デザイン |
| Collection / Calendar / Report | アプリの3タブ（一覧 / カレンダー / 統計） |

---

## 6. コミット

- 作業ブランチは **`v.x.x.xx`** 形式（例：v.3.6.18）。PR は **`master`** へ
- commit message 末尾に `Co-Authored-By: {使用したCladeモデル} <noreply@anthropic.com>`
- commit するファイルは**明示指定**。作業ツリーに元からある無関係な変更
  （`Tickemo.xcodeproj/project.pbxproj`、`Info.plist` など）を巻き込まない
- commit / push はユーザーが言ったときだけ。PR は必ず事前確認

---

- **体制**:
  - このプロジェクトは個人開発で作成しているものである
