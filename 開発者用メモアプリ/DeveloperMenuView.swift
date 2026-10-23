#if DEBUG
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct DeveloperMenuView: View {
    @Query private var ideas: [Idea]

    let currentPlan: AppPlan
    let cloudSyncState: CloudSyncState
    let hasCheckedEntitlements: Bool
    let lastSuccessfulSyncAt: Double

    var body: some View {
        List {
            environmentSection
            appStateSection
            diagnosticsSection
        }
        .navigationTitle("開発者メニュー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var environmentSection: some View {
        Section("実行環境") {
            LabeledContent("構成", value: "Debug")
            LabeledContent("実行先", value: runtimeName)
            LabeledContent("アプリ", value: appVersion)
            LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "不明")
            LabeledContent("OS", value: operatingSystem)
            LabeledContent("端末", value: deviceModel)

            if !ProcessInfo.processInfo.arguments.isEmpty {
                DisclosureGroup("起動引数") {
                    ForEach(ProcessInfo.processInfo.arguments, id: \.self) { argument in
                        Text(argument)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var appStateSection: some View {
        Section("アプリ状態") {
            LabeledContent("ローカルカード", value: "\(ideas.count)件")
            LabeledContent("現在のプラン", value: currentPlan.label)
            LabeledContent("StoreKit", value: hasCheckedEntitlements ? "購入情報を確認済み" : "確認中")
            LabeledContent("同期状態", value: cloudSyncState.label)
            LabeledContent("最終同期", value: lastSyncText)

            if case .needsConfiguration(let message) = cloudSyncState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = cloudSyncState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("診断") {
            ShareLink(item: diagnosticReport, subject: Text("Katachi診断レポート")) {
                Label("診断レポートを共有", systemImage: "square.and.arrow.up")
            }

            Text("レポートにはアプリ・OSのバージョン、端末モデル、カード件数、プラン、同期状態、起動引数が含まれます。カードの内容や購入情報は含みません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "不明"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明"
        return "\(version) (\(build))"
    }

    private var runtimeName: String {
        #if targetEnvironment(simulator)
        "Simulator"
        #else
        "実機"
        #endif
    }

    private var operatingSystem: String {
        #if canImport(UIKit)
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private var deviceModel: String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        "不明"
        #endif
    }

    private var lastSyncText: String {
        guard lastSuccessfulSyncAt > 0 else { return "未同期" }
        return Date(timeIntervalSince1970: lastSuccessfulSyncAt)
            .formatted(date: .abbreviated, time: .shortened)
    }

    private var diagnosticReport: String {
        [
            "Katachi診断レポート",
            "構成: Debug",
            "実行先: \(runtimeName)",
            "アプリ: \(appVersion)",
            "Bundle ID: \(Bundle.main.bundleIdentifier ?? "不明")",
            "OS: \(operatingSystem)",
            "端末: \(deviceModel)",
            "ローカルカード: \(ideas.count)件",
            "現在のプラン: \(currentPlan.label)",
            "StoreKit: \(hasCheckedEntitlements ? "購入情報を確認済み" : "確認中")",
            "同期状態: \(cloudSyncState.label)",
            "最終同期: \(lastSyncText)",
            "起動引数: \(ProcessInfo.processInfo.arguments.joined(separator: " "))"
        ].joined(separator: "\n")
    }
}
#endif
