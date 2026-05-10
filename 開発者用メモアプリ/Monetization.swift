import Foundation
import Combine
import StoreKit

enum BillingProduct: String, CaseIterable, Identifiable {
    case plusMonthly = "katachi.developers.plus.monthly"
    case plusYearly = "katachi.developers.plus.yearly"
    case proMonthly = "katachi.developers.pro.monthly"
    case proYearly = "katachi.developers.pro.yearly"
    case extra25 = "katachi.developers.extra.25"
    case extra100 = "katachi.developers.extra.100"
    case extra200 = "katachi.developers.extra.200"

    var id: String { rawValue }

    var plan: AppPlan? {
        switch self {
        case .plusMonthly, .plusYearly:
            return .plus
        case .proMonthly, .proYearly:
            return .pro
        case .extra25, .extra100, .extra200:
            return nil
        }
    }

    var extraSlotPack: ExtraSlotPack? {
        switch self {
        case .extra25:
            return .small
        case .extra100:
            return .medium
        case .extra200:
            return .large
        case .plusMonthly, .plusYearly, .proMonthly, .proYearly:
            return nil
        }
    }

    var billingCycleLabel: String {
        switch self {
        case .plusMonthly, .proMonthly:
            return "月額"
        case .plusYearly, .proYearly:
            return "年額"
        case .extra25, .extra100, .extra200:
            return "追加枠"
        }
    }

    var fallbackPriceLabel: String {
        switch self {
        case .plusMonthly:
            return "460円"
        case .plusYearly:
            return "4,600円"
        case .proMonthly:
            return "1,200円"
        case .proYearly:
            return "12,000円"
        case .extra25:
            return "100円"
        case .extra100:
            return "300円"
        case .extra200:
            return "500円"
        }
    }

    static func subscriptionProducts(for plan: AppPlan) -> [BillingProduct] {
        switch plan {
        case .free:
            return []
        case .plus:
            return [.plusMonthly, .plusYearly]
        case .pro:
            return [.proMonthly, .proYearly]
        }
    }

    static func extraProduct(for pack: ExtraSlotPack) -> BillingProduct {
        switch pack {
        case .small:
            return .extra25
        case .medium:
            return .extra100
        case .large:
            return .extra200
        }
    }
}

enum PurchaseResultState: Equatable {
    case idle
    case loading
    case purchased(BillingProduct)
    case restored
    case pending
    case cancelled
    case failed(String)

    var message: String? {
        switch self {
        case .idle, .loading:
            return nil
        case .purchased(let product):
            if let plan = product.plan {
                return "\(plan.label)を有効化しました。"
            }
            if let pack = product.extraSlotPack {
                return "\(pack.label)の追加枠を購入しました。"
            }
            return "購入が完了しました。"
        case .restored:
            return "購入情報を復元しました。"
        case .pending:
            return "購入が承認待ちです。"
        case .cancelled:
            return "購入をキャンセルしました。"
        case .failed(let message):
            return message
        }
    }
}

enum PromotionCodeEffect: Equatable {
    case plan(AppPlan)
    case extraSlots(Int)

    var message: String {
        switch self {
        case .plan(let plan):
            return "\(plan.label)を有効化しました。"
        case .extraSlots(let slots):
            return "保存枠を+\(slots)件追加しました。"
        }
    }
}

struct PromotionCode: Identifiable, Equatable {
    let id: String
    let effect: PromotionCodeEffect
    let note: String
    let expiresAt: Date?
    let localRedemptionLimit: Int?

    init(
        id: String,
        effect: PromotionCodeEffect,
        note: String,
        expiresAt: Date? = nil,
        localRedemptionLimit: Int? = 1
    ) {
        self.id = id
        self.effect = effect
        self.note = note
        self.expiresAt = expiresAt
        self.localRedemptionLimit = localRedemptionLimit
    }

    static let all: [PromotionCode] = [
        PromotionCode(
            id: "KFD-PRO-C4C0-365E-91DD-8CAD-29D0-AFD4-1A66-D7EB",
            effect: .plan(.pro),
            note: "開発者・運営確認用のProコード",
            localRedemptionLimit: nil
        ),
        PromotionCode(
            id: "KFD-PLUS-6B4D-846F-D7C0-86BC-A3AB-1C9B-CE34-EFF8",
            effect: .plan(.plus),
            note: "開発者・運営確認用のPlusコード",
            localRedemptionLimit: nil
        ),
        PromotionCode(
            id: "KATACHI-LAUNCH-10",
            effect: .extraSlots(10),
            note: "リリース記念の保存枠+10",
            expiresAt: DateComponents(calendar: .current, year: 2026, month: 12, day: 31).date
        ),
        PromotionCode(
            id: "KATACHI-LAUNCH-25",
            effect: .extraSlots(25),
            note: "キャンペーン用の保存枠+25",
            expiresAt: DateComponents(calendar: .current, year: 2026, month: 12, day: 31).date
        )
    ]

    var isCurrentlyValid: Bool {
        guard let expiresAt else {
            return true
        }
        return Date() <= expiresAt
    }

    static func normalized(_ rawValue: String) -> String {
        rawValue
            .trimmed
            .uppercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "ー", with: "-")
            .replacingOccurrences(of: "−", with: "-")
    }

    static func find(_ rawValue: String) -> PromotionCode? {
        let code = normalized(rawValue)
        return all.first { $0.id == code }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var hasCheckedEntitlements = false
    @Published var state: PurchaseResultState = .idle

    private var updatesTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
    }

    var entitledPlan: AppPlan? {
        if purchasedProductIDs.contains(BillingProduct.proMonthly.rawValue)
            || purchasedProductIDs.contains(BillingProduct.proYearly.rawValue) {
            return .pro
        }
        if purchasedProductIDs.contains(BillingProduct.plusMonthly.rawValue)
            || purchasedProductIDs.contains(BillingProduct.plusYearly.rawValue) {
            return .plus
        }
        return nil
    }

    func start() async {
        if updatesTask == nil {
            updatesTask = listenForTransactionUpdates()
        }
        await refresh()
    }

    func refresh() async {
        state = .loading
        do {
            products = try await Product.products(for: BillingProduct.allCases.map(\.rawValue))
            await updatePurchasedProducts()
            state = .idle
        } catch {
            state = .failed("商品情報を取得できませんでした: \(error.localizedDescription)")
        }
    }

    func product(for billingProduct: BillingProduct) -> Product? {
        products.first { $0.id == billingProduct.rawValue }
    }

    func displayPrice(for billingProduct: BillingProduct) -> String {
        product(for: billingProduct)?.displayPrice ?? billingProduct.fallbackPriceLabel
    }

    func purchase(_ billingProduct: BillingProduct) async -> PurchaseResultState {
        guard let product = product(for: billingProduct) else {
            let nextState: PurchaseResultState = .failed("商品IDがStoreKitに登録されていません: \(billingProduct.rawValue)")
            state = nextState
            return nextState
        }

        state = .loading
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                let nextState: PurchaseResultState = .purchased(billingProduct)
                state = nextState
                return nextState
            case .pending:
                state = .pending
                return .pending
            case .userCancelled:
                state = .cancelled
                return .cancelled
            @unknown default:
                let nextState: PurchaseResultState = .failed("購入結果を処理できませんでした。")
                state = nextState
                return nextState
            }
        } catch {
            let nextState: PurchaseResultState = .failed("購入に失敗しました: \(error.localizedDescription)")
            state = nextState
            return nextState
        }
    }

    func restore() async -> PurchaseResultState {
        state = .loading
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            state = .restored
            return .restored
        } catch {
            let nextState: PurchaseResultState = .failed("購入情報を復元できませんでした: \(error.localizedDescription)")
            state = nextState
            return nextState
        }
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await self.updatePurchasedProducts()
                } catch {
                    await MainActor.run {
                        self.state = .failed("購入情報を検証できませんでした。")
                    }
                }
            }
        }
    }

    private func updatePurchasedProducts() async {
        var productIDs = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else {
                continue
            }
            if transaction.revocationDate == nil {
                productIDs.insert(transaction.productID)
            }
        }
        purchasedProductIDs = productIDs
        hasCheckedEntitlements = true
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

private enum StoreKitError: Error {
    case failedVerification
}
