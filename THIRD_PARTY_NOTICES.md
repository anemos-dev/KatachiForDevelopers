# Third Party Notices

Katachi for Developers uses Apple platform frameworks plus the following Swift Package Manager dependencies for paid cloud sync builds.

- Firebase Apple SDK (`https://github.com/firebase/firebase-ios-sdk.git`)
  - Products: `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`
  - License: Apache License 2.0
- Google Sign-In for iOS (`https://github.com/google/GoogleSignIn-iOS.git`)
  - Product: `GoogleSignIn`
  - License: Apache License 2.0

Before App Store submission, confirm the resolved package versions, bundled privacy manifests, and App Store Connect privacy disclosures match the final build.

The exact transitive dependency set is pinned in `開発者用メモアプリ.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
