# Katachi for Developers

Katachi for Developers is an iPhone app for developers who want to capture rough ideas quickly and turn them into actionable cards later.

The app focuses on developer thought flow: feature ideas, UI improvements, technical research notes, bug hypotheses, article seeds, and lightweight project context can be saved as structured cards instead of disappearing into a generic memo app.

## Concept

**1 idea = 1 card = 1 reusable seed**

Katachi keeps each idea compact, searchable, and easy to revisit. The first release is centered on fast capture, lightweight organization, and rediscovery.

## Main Features

- Quick idea capture
- Card list with previews
- Detail editing
- Search across idea fields
- Filters by kind, status, group, and favorite state
- Sorting by updated date, created date, or priority
- Tags and project context
- Favorite flag
- Local persistence with SwiftData
- Optional billing and cloud sync flows for Plus / Pro plans

## Tech Stack

- SwiftUI
- SwiftData
- StoreKit
- Firebase Auth / Firestore
- Google Sign-In
- Xcode project based iOS app

## Project Structure

```text
.
├── 開発者用メモアプリ/          # App source
├── 開発者用メモアプリTests/     # Unit tests
├── 開発者用メモアプリUITests/   # UI tests
├── docs/                        # Product, release, legal, and review docs
├── firebase/                    # Firestore rules
├── assets/                      # Design and app icon assets
└── 開発者用メモアプリ.xcodeproj
```

## Getting Started

1. Open `開発者用メモアプリ.xcodeproj` in Xcode.
2. Select the `Katachi` app target.
3. Resolve Swift Package Manager dependencies if Xcode has not already done so.
4. Choose an iPhone simulator or a physical iPhone.
5. Build and run.

The app can run in local-only mode. Firebase and Google Sign-In configuration is only required for cloud sync related flows.

## Firebase Setup

Cloud sync uses Firebase when the required SDKs and configuration file are available.

For local development:

1. Add a valid `GoogleService-Info.plist` to the app target.
2. Enable the required Firebase Auth providers.
3. Configure Firestore.
4. Review `firebase/firestore.rules` before deploying rules.

Do not commit production secrets or private service credentials.

## Documentation

- [仕様書](docs/spec-ja.md)
- [開発者メニューとブランチ運用](docs/developer-menu-operations-ja.md)
- [デザイン方針](docs/design.md)
- [収益化セットアップ](docs/monetization-setup-ja.md)
- [β準備チェックリスト](docs/beta-readiness-ja.md)
- [リリースQAチェックリスト](docs/release-qa-checklist-ja.md)
- [App Store審査準備](docs/app-store-review-readiness-ja.md)
- [プライバシーポリシー](docs/privacy-policy-ja.md)
- [利用規約](docs/terms-of-use-ja.md)

## Status

This repository is under active development toward the MVP / beta release of Katachi for Developers.

## License / Notices

See [COPYRIGHT.md](COPYRIGHT.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
