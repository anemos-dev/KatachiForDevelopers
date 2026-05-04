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

## Firebase / Googleログイン

Swift Package Managerで次を追加する。

- `https://github.com/firebase/firebase-ios-sdk.git`
  - `FirebaseAuth`
  - `FirebaseFirestore`
- `https://github.com/google/GoogleSignIn-iOS.git`
  - `GoogleSignIn`

Firebase Consoleから `GoogleService-Info.plist` をダウンロードしてアプリターゲットに追加する。Googleログインを使う場合は、plist内の `REVERSED_CLIENT_ID` をURL Schemeにも設定する。

## Firestore構造

同期先は次の形にしている。

```text
users/{uid}/ideas/{ideaId}
```

`IdeaCloudRecord` がSwiftDataの `Idea` をFirestoreへ保存できる辞書に変換する。
