# Katachi開発ガイド

> **このファイルを読む場面:** カード、検索、SwiftData、プラン・課金、Firebase同期、認証、テスト、Xcode設定を変更するとき。

## 構成

- iOS 17以上、Swift 5、SwiftUI / SwiftData / StoreKit / Firebase Auth・Firestore / Google Sign-In。
- `開発者用メモアプリ/__________App.swift`がSwiftDataとGoogle Sign-Inを構成し、`ContentView.swift`が主要UIです。
- `Item.swift`にカード、分類、プラン、作成制限、テンプレート、SwiftDataの`Idea`があります。
- `Monetization.swift`が商品・購入・プロモーション、`CloudSync.swift`がFirebase初期化、認証、同期状態を担当します。
- `docs/`は仕様・法務・審査・Webサポート、`firebase/`はルール、`assets/`と`release-assets/`は素材です。

## コマンド

```bash
xcodebuild -list -project '開発者用メモアプリ.xcodeproj'
xcodebuild -resolvePackageDependencies -project '開発者用メモアプリ.xcodeproj'
xcodebuild -project '開発者用メモアプリ.xcodeproj' -scheme '開発者用メモアプリ' -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project '開発者用メモアプリ.xcodeproj' -scheme '開発者用メモアプリ' -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

target名とSwift Package依存は`project.pbxproj`で確認済みです。`xcodebuild -list`は依存解決待ちで完了しなかったため、schemeを含むコマンドは未実行です。

## 安全性と検証

- `GoogleService-Info.plist`、本番資格情報、実ユーザーデータをコミットしません。Firebaseなしでもローカル利用できる状態を維持します。
- プラン制限は`IdeaCreationPolicy`、購入はStoreKitの既存境界を通し、テストのために購入判定を偽装しません。
- 同期では競合、ログアウト、削除、再ログイン、ネットワーク失敗を確認し、ルール変更はFirebaseへ勝手にデプロイしません。
- 課金・同期変更は単体テストに加えSandboxまたは適切なテスト構成で確認し、リリース時は既存チェックリストを使います。
