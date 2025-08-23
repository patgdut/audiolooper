import SwiftUI
import StoreKit

/// App 流程管理器，处理引导页、支付页和评分流程
@MainActor
class AppFlowManager: ObservableObject {
    // MARK: - Published Properties
    @Published var showOnboarding = false
    @Published var showPurchaseView = false
    @Published var showRatingAlert = false
    
    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private var hasCompletedInitialFlow = false
    private var isCheckingRating = false  // 添加状态标记
    
    // MARK: - UserDefaults Keys
    private let onboardingSeenKey: String
    private let ratingPromptShownKey: String
    private let firstLaunchKey: String
    
    // MARK: - Dependencies
    private let purchaseModel: PurchaseModel
    
    // MARK: - Initialization
    init(
        purchaseModel: PurchaseModel,
        onboardingSeenKey: String = "OnboardingSeen",
        ratingPromptShownKey: String = "hasShownRatingPrompt",
        firstLaunchKey: String = "hasLaunchedBefore"
    ) {
        self.purchaseModel = purchaseModel
        self.onboardingSeenKey = onboardingSeenKey
        self.ratingPromptShownKey = ratingPromptShownKey
        self.firstLaunchKey = firstLaunchKey
    }
    
    // MARK: - Public Methods
    
    /// 启动时检查并开始流程
    func checkAndStartFlow() {
        let hasSeenOnboarding = userDefaults.bool(forKey: onboardingSeenKey)
        
        Task { @MainActor in
            if !hasSeenOnboarding {
                // 首次启动，显示引导页
                showOnboarding = true
            } else if !purchaseModel.isSubscribed {
                // 已看过引导页但未订阅，显示支付页
                showPurchaseView = true
            } else {
                // 已看过引导页且已订阅，检查是否显示评分
                completeInitialFlowAndCheckRating()
            }
        }
    }
    
    /// 引导页完成回调
    func onboardingCompleted() {
        userDefaults.set(true, forKey: onboardingSeenKey)
        showOnboarding = false
        
        Task { @MainActor in
            if !purchaseModel.isSubscribed {
                showPurchaseView = true
            } else {
                completeInitialFlowAndCheckRating()
            }
        }
    }
    
    /// 支付页面关闭回调
    func purchaseViewDismissed() {
        showPurchaseView = false
        completeInitialFlowAndCheckRating()
    }
    
    /// 处理评分结果
    func handleRatingResponse(loved: Bool) {
        markRatingPromptShown()
        // 如果用户喜欢，则请求 App Store 评分
        if loved {
            requestAppReview()
        }
    }
    
    // MARK: - Private Methods
    
    private func completeInitialFlowAndCheckRating() {
        if !hasCompletedInitialFlow {
            hasCompletedInitialFlow = true
            checkAndShowRatingPrompt()
        }
    }
    
    private func checkAndShowRatingPrompt() {
        // 如果已经在检查中，直接返回
        guard !isCheckingRating else { return }
        
        let hasShownRatingPrompt = userDefaults.bool(forKey: ratingPromptShownKey)
        let isFirstLaunch = userDefaults.bool(forKey: firstLaunchKey)
        
        if !isFirstLaunch {
            userDefaults.set(true, forKey: firstLaunchKey)
            return
        }
        
        if !hasShownRatingPrompt {
            isCheckingRating = true  // 设置检查标记
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.showRatingAlert = true
                self?.isCheckingRating = false  // 重置检查标记
            }
        }
    }
    
    private func markRatingPromptShown() {
        userDefaults.set(true, forKey: ratingPromptShownKey)
    }
    
    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}

// MARK: - View Extension
extension View {
    func withAppFlow(
        manager: AppFlowManager,
        onboardingView: OnboardingView,
        purchaseView: PurchaseView
    ) -> some View {
        self
            .overlay {
                if manager.showOnboarding {
                    OnboardingView(
                        appName: onboardingView.appName,
                        features: onboardingView.features,
                        color: onboardingView.color,
                        onboardingCompleted: {
                            manager.onboardingCompleted()
                        }
                    )
                }
            }
            .overlay {
                if manager.showPurchaseView {
                    purchaseView
                }
            }
            .alert(NSLocalizedString("rating_alert_title", comment: "Rating alert title"), isPresented: Binding(
                get: { manager.showRatingAlert },
                set: { manager.showRatingAlert = $0 }
            )) {
                Button(NSLocalizedString("love_it_button", comment: "Love it button")) {
                    manager.handleRatingResponse(loved: true)
                }
                Button(NSLocalizedString("maybe_later_button", comment: "Maybe later button")) {
                    manager.handleRatingResponse(loved: false)
                }
            } message: {
                Text(NSLocalizedString("rating_alert_message", comment: "Rating alert message"))
            }
            .onAppear {
                manager.checkAndStartFlow()
            }
    }
} 
