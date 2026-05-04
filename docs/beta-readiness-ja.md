# Katachi for Developers βテスト実施ガイド

最終更新: 2026-04-11

## 1. 現在の到達点

- 仕様確定済み（[spec-ja.md](/Volumes/SSD-SCHU3A/アプリ開発/開発者用メモアプリ/docs/spec-ja.md)）
- MVP機能実装済み
- アプリ本体ビルド成功（署名無効の検証ビルド）
- test build（`build-for-testing`）成功
- Release archive生成成功（`/tmp/Katachi.xcarchive`）

## 2. 実装済み機能（β対象）

- Katachiカード作成
- カード一覧表示
- カード詳細表示
- カード編集
- 削除
- お気に入り切替
- 検索（複数項目横断）
- フィルタ（種類 / ステータス / お気に入り）
- 並び替え（更新日 / 作成日 / 優先度）

## 3. ローカル検証コマンド

### 3.1 アプリ本体ビルド

```bash
xcodebuild \
  -project '開発者用メモアプリ.xcodeproj' \
  -scheme '開発者用メモアプリ' \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/idea-memo-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build
```

### 3.2 テストビルド

```bash
xcodebuild \
  -project '開発者用メモアプリ.xcodeproj' \
  -scheme '開発者用メモアプリ' \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/idea-memo-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build-for-testing
```

## 4. TestFlight前チェックリスト

配布前に最低限この順で確認する。

1. Signing & CapabilitiesでTeamを設定（現在は未設定）
2. Bundle Identifier確認（現在: `com.Anemos.KatachiDevelopers`）
3. Version / Build番号を更新（現在: `0.1.0` / `1`）
4. App Iconを最終版へ差し替え
5. Xcode GUIで署名付きArchiveを作成
6. App Store ConnectへUpload
7. Internal Testerでインストール・起動確認

## 4.1 署名無効でのArchive検証コマンド

```bash
xcodebuild \
  -project '開発者用メモアプリ.xcodeproj' \
  -scheme '開発者用メモアプリ' \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/idea-memo-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  archive -archivePath /tmp/Katachi.xcarchive
```

## 5. β受け入れテスト（手動）

### 5.1 作成フロー

- タイトルのみで保存できる
- `何を思いついたか` のみで保存できる
- タイトル空欄時に仮タイトル化される

### 5.2 一覧フロー

- 作成後にカードが一覧へ反映
- カードにステータス / 種類 / タグ / 更新相対時刻が表示
- タグが4件以上のとき `+N` 表示になる

### 5.3 管理フロー

- 検索で該当カードが絞り込まれる
- フィルタ条件の適用 / リセットが機能する
- 並び替えで順序が期待通り変わる
- お気に入り切替と削除が反映される

### 5.4 編集フロー

- 詳細画面から編集に入れる
- 保存後に一覧へ更新内容が反映される
- 次アクション、タグ、ステータス変更が保持される

## 6. 既知の運用注意点

- 現在のワークスペースではSimulatorサービスが不安定な場合があるため、CLI上での`xcodebuild test`実行は環境依存で失敗する可能性がある
- その場合はXcode GUIから実機または安定したSimulatorで最終テストを実施する

## 7. βフィードバック収集項目

- 20秒以内で発想を保存できるか
- 一覧だけで「何のアイデアか」を思い出せるか
- 項目分割は負担か、整理に役立つか
- ステータス定義は自然か
- 次アクション欄が行動につながるか
