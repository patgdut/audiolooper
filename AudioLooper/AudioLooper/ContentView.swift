//
//  ContentView.swift
//  AudioLooper
//
//  Created by 任健生 on 2025/8/23.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var purchaseModel = PurchaseModel()
    @StateObject private var appFlowManager: AppFlowManager
    @State private var showPurchase = false
    
    init() {
        let purchaseModel = PurchaseModel()
        let appFlowManager = AppFlowManager(purchaseModel: purchaseModel)
        self._purchaseModel = StateObject(wrappedValue: purchaseModel)
        self._appFlowManager = StateObject(wrappedValue: appFlowManager)
    }
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad view - directly show main view but keep AppFlow functionality
                AudioLooperView()
                    .environmentObject(purchaseModel)
                    .withAppFlow(
                        manager: appFlowManager,
                        onboardingView: OnboardingView(
                            appName: NSLocalizedString("audio_looper", comment: "App name"),
                            features: [
                                Feature(
                                    title: NSLocalizedString("loop_audios_custom_count", comment: "Feature title"),
                                    description: NSLocalizedString("loop_audios_custom_count_desc", comment: "Feature description"),
                                    icon: "repeat"
                                ),
                                Feature(
                                    title: NSLocalizedString("time_range_selection", comment: "Feature title"),
                                    description: NSLocalizedString("time_range_selection_desc", comment: "Feature description"),
                                    icon: "slider.horizontal.below.rectangle"
                                ),
                                Feature(
                                    title: NSLocalizedString("high_quality_export", comment: "Feature title"),
                                    description: NSLocalizedString("high_quality_export_desc", comment: "Feature description"),
                                    icon: "music.note"
                                ),
                                Feature(
                                    title: NSLocalizedString("premium_unlimited_loops", comment: "Feature title"),
                                    description: NSLocalizedString("premium_unlimited_loops_desc", comment: "Feature description"),
                                    icon: "star.circle.fill"
                                )
                            ],
                            color: .blue,
                            onboardingCompleted: {}
                        ),
                        purchaseView: PurchaseView(isPresented: .init(
                            get: { appFlowManager.showPurchaseView },
                            set: { newValue in
                                if !newValue {
                                    appFlowManager.purchaseViewDismissed()
                                }
                            }
                        ))
                    )
            } else {
                // iPhone view - keep original navigation style
                AudioLooperView()
                    .environmentObject(purchaseModel)
                    .withAppFlow(
                        manager: appFlowManager,
                        onboardingView: OnboardingView(
                            appName: NSLocalizedString("audio_looper", comment: "App name"),
                            features: [
                                Feature(
                                    title: NSLocalizedString("loop_audios_custom_count", comment: "Feature title"),
                                    description: NSLocalizedString("loop_audios_custom_count_desc", comment: "Feature description"),
                                    icon: "repeat"
                                ),
                                Feature(
                                    title: NSLocalizedString("time_range_selection", comment: "Feature title"),
                                    description: NSLocalizedString("time_range_selection_desc", comment: "Feature description"),
                                    icon: "slider.horizontal.below.rectangle"
                                ),
                                Feature(
                                    title: NSLocalizedString("high_quality_export", comment: "Feature title"),
                                    description: NSLocalizedString("high_quality_export_desc", comment: "Feature description"),
                                    icon: "music.note"
                                ),
                                Feature(
                                    title: NSLocalizedString("premium_unlimited_loops", comment: "Feature title"),
                                    description: NSLocalizedString("premium_unlimited_loops_desc", comment: "Feature description"),
                                    icon: "star.circle.fill"
                                )
                            ],
                            color: .blue,
                            onboardingCompleted: {}
                        ),
                        purchaseView: PurchaseView(isPresented: .init(
                            get: { appFlowManager.showPurchaseView },
                            set: { newValue in
                                if !newValue {
                                    appFlowManager.purchaseViewDismissed()
                                }
                            }
                        ))
                    )
            }
        }
    }
}

#Preview {
    ContentView()
}
