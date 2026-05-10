# Katachi for Developers 課金・Firebase接続メモ

## StoreKit商品ID

App Store ConnectのIn-App Purchase / Subscriptionsには、アプリ内の `BillingProduct` と同じIDを登録する。

| 種類 | 商品ID | 価格 |
| --- | --- | --- |
| Plus 月額 | `katachi.developers.plus.monthly` | 460円 |
| Plus 年額 | `katachi.developers.plus.yearly` | 4,600円 |
| Pro 月額 | `katachi.developers.pro.monthly` | 1,200円 |
| Pro 年額 | `katachi.developers.pro.yearly` | 12,000円 |
| 追加25件 | `katachi.developers.extra.25` | 100円 |
| 追加100件 | `katachi.developers.extra.100` | 300円 |
| 追加200件 | `katachi.developers.extra.200` | 500円 |

サブスクは同じSubscription Groupに入れる。追加枠はFree向けの消耗型アイテムとして扱う。

App Store上のアプリ名は `Katachi for Developers`、ホーム画面表示名は `Katachi` とする。将来 `Katachi for Designers` を別アプリとして出す場合は、商品IDも `katachi.designers.*` のように分ける。

## 特典コード

設定タブの「特典コード」から、App Store購入とは別に端末内でプランや保存枠を有効化できる。

- `KFD-PRO-C4C0-365E-91DD-8CAD-29D0-AFD4-1A66-D7EB`: Proを有効化
- `KFD-PLUS-6B4D-846F-D7C0-86BC-A3AB-1C9B-CE34-EFF8`: Plusを有効化
- `KATACHI-LAUNCH-10`: Free保存枠を+10（2026-12-31まで）
- `KATACHI-LAUNCH-25`: Free保存枠を+25（2026-12-31まで）

保存枠追加の特典コードは同じ端末で二重適用されない。Pro / Plusの特典コードは確認・運営用途として、Freeに戻した後も再適用できる。完全な一人一回のシリアルコード、失効、配布数制御、不正利用防止を行う場合は、Firebase側に特典コード台帳を置いてサーバー検証に切り替える。

紹介コード:

- `KATACHI-FRIEND-10`: Free保存枠を+10
- `KFD-INVITE-10`: Free保存枠を+10

紹介特典は同じ端末で一度だけ適用される。

## Firebase / Googleログイン / Sign in with Apple

Swift Package Managerで次を追加済み。

- `https://github.com/firebase/firebase-ios-sdk.git`（`12.12.1` から次のメジャー未満）
  - `FirebaseCore`
  - `FirebaseAuth`
  - `FirebaseFirestore`
- `https://github.com/google/GoogleSignIn-iOS.git`（`9.1.0` から次のメジャー未満）
  - `GoogleSignIn`

Firebase Consoleから `GoogleService-Info.plist` をダウンロードしてアプリターゲットに追加する。Googleログインを使う場合は、plist内の `REVERSED_CLIENT_ID` をURL Schemeにも設定する。Googleログインを出すため、審査対策としてSign in with Appleも同じFirebase Authへ接続している。

Xcodeでの残作業:

- Firebase Consoleで Authentication > Sign-in method > Google を有効化
- Firebase Consoleで Authentication > Sign-in method > Apple を有効化
- Apple DeveloperのIdentifiersでSign in with Apple Capabilityを有効化
- `GoogleService-Info.plist` を `開発者用メモアプリ` ターゲットに追加
- Target > Info > URL Types に `REVERSED_CLIENT_ID` をURL Schemeとして追加
- Target > Build Settings > Other Linker Flags に `-ObjC` が入っていることを確認
- `firebase/firestore.rules` をFirebaseプロジェクトにデプロイ
- Sandbox/TestFlightでSign in with Apple、Googleログイン、同期、ログアウト、クラウドアカウント削除を確認

## Firestore構造

同期先は次の形にしている。

```text
users/{uid}/ideas/{ideaId}
```

`IdeaCloudRecord` がSwiftDataの `Idea` をFirestoreへ保存できる辞書に変換する。

Firestore Security Rulesは `firebase/firestore.rules` に配置済み。本人の `users/{uid}/ideas/{ideaId}` だけを読み書きできる前提にしている。

## DBコストを守る設計

- 一覧表示はホーム、検索、グループ詳細ともに24件ずつ追加表示する。
- Firestore同期は、同期開始時にクラウド側のカードをページング取得して端末へ復元し、同じIDのカードは更新日時が新しい方を採用する。
- 復元後、初回以外は前回成功同期以降に更新された端末側カードだけを書き込む。
- 端末側でカードを削除した場合、ログイン済みのPlus / ProではFirestore上の同一カードも削除する。
- 同期中に作成されたカードを取りこぼさないよう、同期開始時刻を保存基準にする。
- Firestoreから一覧取得を実装する場合も、`limit(24)` とcursorベースのページングを使う。`offset` は読み取り課金が増えるため使わない。
- 将来クラウドから一覧を直接読む場合は、一覧用の軽いsummaryドキュメントと本文ドキュメントを分ける。Firestoreは1件readでドキュメント全体を返すため、本文を毎回一覧で読まない。
