// PurchaseModel SwiftUI
// Created by Adam Lyttle on 7/18/2024

// Make cool stuff and share your build with me:

//  --> x.com/adamlyttleapps
//  --> github.com/adamlyttleapps

import Foundation
import StoreKit

@MainActor
class PurchaseModel: ObservableObject {
    
    // MARK: - Product IDs
    static let yearlySubscriptionId = "com.coolappbox.audiolooper.yearly"
    static let weeklySubscriptionId = "com.coolappbox.audiolooper.weekly"
    
    @Published var productIds: [String]
    @Published var productDetails: [PurchaseProductDetails] = []
    @Published var products: [Product] = []

    @Published var isSubscribed: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var isFetchingProducts: Bool = false
    @Published var subscriptionExpirationDate: Date? = nil
    
    private var updateListenerTask: Task<Void, Error>? = nil
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults keys
    private let subscriptionStatusKey = "subscription_status"
    private let subscriptionExpirationKey = "subscription_expiration"
    private let subscriptionProductIdKey = "subscription_product_id"
    
    init() {
        // 使用静态常量初始化产品 ID
        self.productIds = [PurchaseModel.yearlySubscriptionId, PurchaseModel.weeklySubscriptionId]
        self.productDetails = [
            PurchaseProductDetails(
                price: "$17.99",
                productId: PurchaseModel.yearlySubscriptionId,
                duration: NSLocalizedString("year", comment: "year"),
                durationPlanName: NSLocalizedString("yearly_plan", comment: "Yearly plan name"),
                hasTrial: false
            ),
            PurchaseProductDetails(
                price: "$4.99",
                productId: PurchaseModel.weeklySubscriptionId,
                duration:  NSLocalizedString("week", comment: "week"),
                durationPlanName: NSLocalizedString("three_day_trial", comment: "3-day trial plan name"),
                hasTrial: true
            )
        ]
        
        // Load saved subscription status
        loadSavedSubscriptionStatus()
        
        // Start listening for transactions when initializing
        updateListenerTask = listenForTransactions()
        
        // Load products when initializing
        Task {
            await loadProducts()
        }
        
        // Check subscription status
        Task {
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // 加载保存的订阅状态
    private func loadSavedSubscriptionStatus() {
        self.isSubscribed = userDefaults.bool(forKey: subscriptionStatusKey)
        if let expirationDate = userDefaults.object(forKey: subscriptionExpirationKey) as? Date {
            self.subscriptionExpirationDate = expirationDate
            // 检查是否过期
            if expirationDate < Date() {
                self.isSubscribed = false
                self.subscriptionExpirationDate = nil
                clearSubscriptionData()
            }
        }
    }
    
    // 保存订阅状态
    private func saveSubscriptionStatus(productId: String, expirationDate: Date) {
        userDefaults.set(true, forKey: subscriptionStatusKey)
        userDefaults.set(expirationDate, forKey: subscriptionExpirationKey)
        userDefaults.set(productId, forKey: subscriptionProductIdKey)
        self.subscriptionExpirationDate = expirationDate
    }
    
    // 清除订阅数据
    private func clearSubscriptionData() {
        userDefaults.removeObject(forKey: subscriptionStatusKey)
        userDefaults.removeObject(forKey: subscriptionExpirationKey)
        userDefaults.removeObject(forKey: subscriptionProductIdKey)
        self.isSubscribed = false
        self.subscriptionExpirationDate = nil
    }
    
    // 获取订阅剩余时间（天数）
    func getRemainingDays() -> Int? {
        guard let expirationDate = subscriptionExpirationDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return components.day
    }
    
    // 检查是否处于订阅状态
    func checkSubscriptionStatus() -> (isSubscribed: Bool, remainingDays: Int?) {
        guard let expirationDate = subscriptionExpirationDate else {
            return (false, nil)
        }
        
        if expirationDate > Date() {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
            return (true, components.day)
        } else {
            clearSubscriptionData()
            return (false, nil)
        }
    }
    
    // 获取格式化的到期时间
    func getFormattedExpirationDate() -> String? {
        guard let expirationDate = subscriptionExpirationDate else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: expirationDate)
    }
    
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    let transaction = try await result.payloadValue
                    // Handle transaction here
                    await self.handleTransaction(transaction)
                    
                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    print("Transaction failed verification: \(error)")
                }
            }
        }
    }
    
    @MainActor
    func loadProducts() async {
        self.isFetchingProducts = true
        
        do {
            // Request products from the App Store
            let storeProducts = try await Product.products(for: Set(productIds))
            self.products = storeProducts
            
            // Update product details with actual prices
            for product in storeProducts {
                if let index = self.productDetails.firstIndex(where: { $0.productId == product.id }) {
                    self.productDetails[index].price = product.displayPrice
                }
            }
        } catch {
            print("Failed to load products: \(error)")
        }
        
        self.isFetchingProducts = false
    }
    
    @MainActor
    func purchaseSubscription(productId: String) {
        guard let product = products.first(where: { $0.id == productId }) else {
            print("Product not found: \(productId)")
            return
        }
        
        self.isPurchasing = true
        
        Task {
            do {
                let result = try await product.purchase()
                
                switch result {
                case .success(let verification):
                    let transaction = try await verification.payloadValue
                    await handleTransaction(transaction)
                    await transaction.finish()
                    
                case .userCancelled:
                    break
                    
                case .pending:
                    break
                    
                default:
                    break
                }
            } catch {
                print("Purchase failed: \(error)")
            }
            
            self.isPurchasing = false
        }
    }
    
    @MainActor
    func restorePurchases() {
        Task {
            do {
                try await AppStore.sync()
                await updateSubscriptionStatus()
            } catch {
                print("Failed to restore purchases: \(error)")
            }
        }
    }
    
    @MainActor
    private func handleTransaction(_ transaction: Transaction) async {
        // 使用静态常量检查产品 ID
        if transaction.productID == PurchaseModel.yearlySubscriptionId ||
           transaction.productID == PurchaseModel.weeklySubscriptionId {
            self.isSubscribed = true
            
            // 计算订阅到期时间
            if let expirationDate = transaction.expirationDate {
                saveSubscriptionStatus(productId: transaction.productID, expirationDate: expirationDate)
            }
        }
    }
    
    @MainActor
    private func updateSubscriptionStatus() async {
        do {
            var foundActiveSubscription = false
            // Check all subscription groups
            for await result in Transaction.currentEntitlements {
                do {
                    let transaction = try await result.payloadValue
                    // 使用静态常量检查产品 ID
                    if transaction.productID == PurchaseModel.yearlySubscriptionId ||
                       transaction.productID == PurchaseModel.weeklySubscriptionId {
                        if let expirationDate = transaction.expirationDate {
                            if expirationDate > Date() {
                                foundActiveSubscription = true
                                saveSubscriptionStatus(productId: transaction.productID, expirationDate: expirationDate)
                                break
                            }
                        }
                    }
                } catch {
                    print("Failed to verify transaction: \(error)")
                }
            }
            
            // If we get here and haven't found an active subscription, clear the data
            if !foundActiveSubscription {
                clearSubscriptionData()
            }
        }
    }
    
    // 定期检查订阅状态
    func startSubscriptionCheck() {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateSubscriptionStatus()
            }
        }
    }
}

class PurchaseProductDetails: ObservableObject, Identifiable {
    let id: UUID
    
    @Published var price: String
    @Published var productId: String
    @Published var duration: String
    @Published var durationPlanName: String
    @Published var hasTrial: Bool
    
    init(price: String = "", productId: String = "", duration: String = "", durationPlanName: String = "", hasTrial: Bool = false) {
        self.id = UUID()
        self.price = price
        self.productId = productId
        self.duration = duration
        self.durationPlanName = durationPlanName
        self.hasTrial = hasTrial
    }
}


