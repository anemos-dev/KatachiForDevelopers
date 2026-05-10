# Katachi for Developers App Store審査準備チェックリスト

最終更新: 2026-05-09

## 提出前の必須判定

現在のコードは、Free版のローカル保存、StoreKit 2の購入導線、Firebase / Google Sign-In SDK接続、Sign in with Apple、Firestoreへのアップロード/復元を含む同期、ログアウト、クラウドアカウント削除、初回起動時の利用規約同意、法務/プライバシー画面まで準備済み。

ただし、Plus / ProをApp Storeに出す場合は、次が完了するまで提出しない。

- App Store Connectに `katachi.developers.*` の商品IDを登録
- サブスク商品をアプリバージョンの「App内課金とサブスクリプション」に紐付け
- Firebase ConsoleでGoogleログインを有効化
- Firebase ConsoleでAppleログインを有効化
- Apple DeveloperのIdentifiersでSign in with Apple Capabilityを有効化
- `GoogleService-Info.plist` をアプリターゲットへ追加
- `GoogleService-Info.plist` の `REVERSED_CLIENT_ID` をURL Schemeへ追加
- Firestore Security Rulesをデプロイ
- Cloud同期を実機またはSandboxで確認
- Privacy Policy / Terms of Useを公開URLに配置し、App Store Connectのメタデータへ設定

上記が未完了なら、初回リリースはFree版のみで出す方が審査リスクが低い。

## アプリ内で対応済み

- ホーム画面表示名: `Katachi`
- App Store表示名: `Katachi for Developers`
- Bundle ID: `com.Anemos.KatachiDevelopers`
- Version: `1.0.0`
- iOS Deployment Target: `17.0`
- PrivacyInfo.xcprivacyを追加
- UserDefaultsのRequired Reason API: `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`
- Firebase同期用のEmail Address、User ID、Other User Content、Purchase HistoryをApp Functionality目的で申告
- アプリ内から「法務・プライバシー」画面へ到達可能
- 初回起動時に利用規約とプライバシーポリシーを表示し、同意しないと本体画面へ進めない
- 利用規約にOS非対応、返金手続き、データ消失、クラウド同期、サービス終了、免責の説明を追加
- 同期ボタンはFirestoreから既存データを復元し、端末側とクラウド側のうち更新日時が新しい内容を残す
- 端末側で削除したカードは、ログイン済みのPlus / ProではFirestore上の同一カードも削除する
- サブスク画面に自動更新、解約、管理方法を明記
- Restore Purchases導線を設置
- 追加保存枠をFree向けの消耗型アイテムとして説明
- Sign in with Apple / Googleログイン後のログアウトとクラウドアカウント削除導線を設置
- 期限メモ、検索履歴、紹介コード、特典コード期限/端末内回数制限、初回サンプルカードを実装
- App Store Connect入力案、公開ページ下書き、リリース前QAチェックリストを `docs/` に追加

## App Store Connect メタデータ案

### アプリ名

Katachi for Developers

### サブタイトル

開発アイデアを実装候補に育てる

### カテゴリ

- Primary: Productivity
- Secondary: Developer Tools

### 年齢制限

通常は4+想定。ユーザー生成コンテンツは端末内または本人のクラウド領域に保存され、公開フィードや他ユーザー交流はない。

### Privacy Nutrition Label

Firebase / Googleログインを含むビルドで出す場合:

- Contact Info: Email Address
- Identifiers: User ID
- User Content: Other User Content
- Purchases: Purchase History
- Purpose: App Functionality
- Linked to User: Yes
- Used for Tracking: No

Firebase Analyticsや広告SDKを追加する場合は、この表記を再確認する。

SDKを外してFree版のみで出す別ビルドにする場合は、PrivacyInfoとApp Store ConnectのPrivacy Nutrition Labelを `Data Not Collected / Tracking: No` に戻す。

## App Review Notes案

```text
Katachi for Developers is a productivity app for capturing and organizing development ideas.

Free features work without login. Plus / Pro use Apple In-App Purchase and enable cloud sync after sign-in.
Restore Purchases is available on the Plan screen.

The app does not include ads, third-party tracking, public user-generated content, or external payment links.
```

Plus / Proを提出する場合は、Review NotesにSandboxで購入・復元・Sign in with Apple・Googleログイン・同期・ログアウト・クラウドアカウント削除を確認できる手順を追記する。

## 権利・商標チェック

提出前に必ず実施する。

- `Katachi` と `Katachi for Developers` の商標検索
  - J-PlatPat
  - USPTO
  - WIPO Global Brand Database
- App Storeで同名/近似アプリ検索
- アイコンがApple、App Store、Xcode、Firebase、Google公式アイコンに似ていないか確認
- スクリーンショットに第三者の商標、実在サービス名、個人情報、顧客情報を含めない
- サンプルカードには自作の架空データのみ使う

商標の最終判断は弁理士または法律専門家に確認する。

## 提出直前チェック

- XcodeでProduct > Archiveが成功
- iOS Deployment Targetが `17.0` になっている
- Versionが `1.0.0`、Buildが提出済みビルドより大きい
- Product > Generate Privacy ReportでPrivacyInfoの内容を確認
- App Store ConnectのPrivacy Policy URLとSupport URLが有効
- Terms URL、User Privacy Choices URL、Support URLの `TODO` を公開情報へ置き換える
- アプリ内の法務画面と公開Privacy Policy / Termsの内容が矛盾していない
- サブスク価格、期間、更新条件、解約方法がアプリ内とApp Store Connectで一致
- すべてのIAP商品がアプリバージョンに紐付いている
- アプリ内に外部決済リンクや外部購入誘導がない
- Cloud同期を出す場合、削除・ログアウト・復元の導線を手動確認
