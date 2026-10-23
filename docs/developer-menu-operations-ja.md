# 開発者メニューとブランチ運用

このアプリでは、グルメップと同じく、通常版の `main` と開発用の `developer-menu` を分けて運用します。開発者メニューのUIはDebugビルドだけに含め、`main` に入れないでください。

## ブランチの役割

- `main`: 通常版のアプリと公開用ドキュメントを管理します。
- `developer-menu`: `main` の更新を取り込みながら、開発者メニューや開発専用機能を保持します。
- `feature/*`: 必要に応じて機能ごとの作業に使います。開発者メニュー本体の変更は `developer-menu` に反映します。

開発者メニューを通常版に含めないため、`DeveloperMenuView` と `developerMenuLink` を含む変更を `developer-menu` から `main` に取り込まないでください。

## 開発者メニュー

アプリの設定タブにある「開発者メニュー」は `#if DEBUG` で囲まれており、Releaseビルドには表示されません。実行環境、アプリとOSのバージョン、Bundle ID、端末モデル、ローカルカード件数、プラン、StoreKit確認状況、同期状態を確認できます。診断レポートを共有するときは、起動引数に機密情報が含まれていないか確認してください。

購入状態や同期設定を書き換える操作は置かず、状況確認と診断レポートの共有に限定しています。

## GitHub Actions

### iOS Build

`.github/workflows/ios-build.yml` は、対象ファイルを含むPull Request、`main` または `developer-menu` へのpush、手動実行でiOS Simulator向けのビルドを行います。署名なしで `xcodebuild build` を実行し、XCTestは起動しません。

### mainからdeveloper-menuへの同期

`.github/workflows/sync-developer-menu.yml` は `main` へのpushで起動し、`main` を `developer-menu` にマージしてpushします。競合がある場合はジョブが失敗するため、競合を解消してから再実行してください。`main` に開発者メニューのコードが入っていた場合も同期を停止します。

この同期ワークフローを有効にするには、ファイル自体を既定ブランチの `main` に含める必要があります。`developer-menu` の変更をそのまま `main` へPull Requestにすると、開発者メニュー本体まで入るため、同期ワークフローの導入は別の作業ブランチで行ってください。

1. `main` から導入用ブランチを作ります。
2. `.github/workflows/ios-build.yml` と `.github/workflows/sync-developer-menu.yml` を導入用ブランチへ追加します。
3. 開発者メニューのSwiftファイルを含めずに、導入用ブランチから `main` へPull Requestを作成してマージします。
4. 開発者メニューの変更を `developer-menu` にpushします。
5. 以後、`main` へのpushで同期が起動します。GitHub Actionsの実行履歴で結果を確認できます。

同期ワークフローには `contents: write` を指定しています。ブランチルールなどでActionsのpushが拒否される場合は、GitHub側のルールを確認してください。

## 現在のセットアップ状況

- GitHubに `developer-menu` ブランチを `main` 起点で作成済みです。
- ローカルの `developer-menu` は `origin/developer-menu` を追跡します。
- 開発者メニューとActionsの変更は現在ローカルにあります。commit/push前なので、GitHub Actionsへの登録と実行はまだ有効になっていません。
- 既存の未コミット変更を含め、push前に `git status` と差分を確認してください。

## 検証

ビルド確認には次のコマンドを使います。

```bash
xcodebuild -project '開発者用メモアプリ.xcodeproj' \
  -scheme '開発者用メモアプリ' \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

ローカルでは上記のiOS Simulator向けビルドが成功しています。GitHub Actionsの実行結果は、ワークフローをGitHubへ反映した後に確認してください。
