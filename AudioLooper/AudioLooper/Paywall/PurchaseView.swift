// PurchaseView SwiftUI
// Created by Adam Lyttle on 7/18/2024

import SwiftUI

struct PurchaseView: View {
    
    @StateObject var purchaseModel: PurchaseModel = PurchaseModel()
    
    @State private var shakeDegrees = 0.0
    @State private var shakeZoom = 0.9
    @State private var showCloseButton = false
    @State private var progress: CGFloat = 0.0

    @Binding var isPresented: Bool
    
    @State var showNoneRestoredAlert: Bool = false
    @State private var showTermsActionSheet: Bool = false

    @State private var freeTrial: Bool = true
    @State private var selectedProductId: String = ""
    
    let color: Color = Color.blue
    
    private let allowCloseAfter: CGFloat = 5.0 //time in seconds until close is allows
    
    var hasCooldown: Bool = true
    
    let placeholderProductDetails: [PurchaseProductDetails] = [
        PurchaseProductDetails(price: "-", productId: "demo", duration: "week", durationPlanName: "week", hasTrial: false),
        PurchaseProductDetails(price: "-", productId: "demo", duration: "week", durationPlanName: "week", hasTrial: false)
    ]
    
    var callToActionText: String {
        return NSLocalizedString("continue_button", comment: "Continue button")
    }
    
    var calculateFullPrice: Double? {
        if let weeklyPriceString = purchaseModel.productDetails.first(where: {$0.duration == "week"})?.price {
            
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency

            if let number = formatter.number(from: weeklyPriceString) {
                let weeklyPriceDouble = number.doubleValue
                return weeklyPriceDouble * 52
            }
            
            
        }
        
        return nil
    }
    
    var calculatePercentageSaved: Int {
        if let calculateFullPrice = calculateFullPrice, let yearlyPriceString = purchaseModel.productDetails.first(where: {$0.duration == "year"})?.price {
            
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency

            if let number = formatter.number(from: yearlyPriceString) {
                let yearlyPriceDouble = number.doubleValue
                
                let saved = Int(100 - ((yearlyPriceDouble / calculateFullPrice) * 100))
                
                if saved > 0 {
                    return saved
                }
                
            }
            
        }
        return 90
    }
    
    // AudioExtractor specific features
    static func createFeatures() -> [PurchaseFeatureView] {
        return [
            PurchaseFeatureView(title: NSLocalizedString("unlimited_duration", comment: "Unlimited duration feature"), icon: "infinity.circle", color: .blue),
            PurchaseFeatureView(title: NSLocalizedString("all_audio_formats", comment: "All audio formats feature"), icon: "waveform.badge.plus", color: .blue),
            PurchaseFeatureView(title: NSLocalizedString("fast_processing", comment: "Fast processing feature"), icon: "bolt.circle", color: .blue),
            PurchaseFeatureView(title: NSLocalizedString("ad_free_experience", comment: "Ad-free experience feature"), icon: "checkmark.seal.fill", color: .blue)
        ]
    }

    var body: some View {
        ZStack (alignment: .top) {
            // Add white background
            Color.white
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack {
                    HStack {
                        Spacer()
                        
                        if hasCooldown && !showCloseButton {
                            Circle()
                                .trim(from: 0.0, to: progress)
                                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                                .opacity(0.1 + 0.1 * self.progress)
                                .rotationEffect(Angle(degrees: -90))
                                .frame(width: 20, height: 20)
                        }
                        else {
                            Image(systemName: "multiply")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, alignment: .center)
                                .clipped()
                                .onTapGesture {
                                    isPresented = false
                                }
                                .opacity(0.2)
                        }
                    }
                    .padding(.top)

                    VStack (spacing: 20) {
                        
                        ZStack {
                            Image("PurchaseHeroIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 150, alignment: .center)
                                .cornerRadius(30)
                                .scaleEffect(shakeZoom)
                                .rotationEffect(.degrees(shakeDegrees))
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        startShaking()
                                    }
                                }
                        }
                        
                        VStack (spacing: 10) {
                            Text(NSLocalizedString("unlock_premium_access", comment: "Unlock premium access title"))
                                .font(.system(size: 30, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.black)
                            VStack (alignment: .leading) {
                                // Use Coin Counter specific features
                                ForEach(PurchaseView.createFeatures(), id: \.title) { feature in
                                    feature
                                }
                            }
                            .font(.system(size: 19))
                            .foregroundColor(.black)
                            .padding(.top)
                        }
                        
                        Spacer()
                        
                        VStack (spacing: 20) {
                            VStack (spacing: 10) {
                                
                                let productDetails = purchaseModel.isFetchingProducts ? placeholderProductDetails : purchaseModel.productDetails
                                
                                ForEach(productDetails) { productDetails in
                                    
                                    Button(action: {
                                        withAnimation {
                                            selectedProductId = productDetails.productId
                                        }
                                        self.freeTrial = productDetails.hasTrial
                                    }) {
                                        VStack {
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    Text(productDetails.durationPlanName)
                                                        .font(.headline.bold())
                                                    if productDetails.hasTrial {
                                                        Text(String(format: NSLocalizedString("then_price_per_duration", comment: "Trial pricing format"), productDetails.price, productDetails.duration))
                                                            .opacity(0.8)
                                                    }
                                                    else {
                                                        HStack (spacing: 0) {
                                                            if let calculateFullPrice = calculateFullPrice, //round down
                                                               let calculateFullPriceLocalCurrency = toLocalCurrencyString(calculateFullPrice),
                                                               calculateFullPrice > 0
                                                            {
                                                                //shows the full price based on weekly calculaation
                                                                Text("\(calculateFullPriceLocalCurrency) ")
                                                                    .strikethrough()
                                                                    .opacity(0.4)
                                                                
                                                            }
                                                            Text(String(format: NSLocalizedString("price_per_duration", comment: "Regular pricing format"), productDetails.price, productDetails.duration))
                                                        }
                                                        .opacity(0.8)
                                                    }
                                                }
                                                Spacer()
                                                if productDetails.hasTrial {
                                                }
                                                else {
                                                    VStack {
                                                        Text(String(format: NSLocalizedString("save_percent", comment: "Save percentage"), calculatePercentageSaved))
                                                            .font(.caption.bold())
                                                            .foregroundColor(.white)
                                                            .padding(8)
                                                    }
                                                    .background(Color.red)
                                                    .cornerRadius(6)
                                                }
                                                
                                                ZStack {
                                                    Image(systemName: (selectedProductId == productDetails.productId) ? "circle.fill" : "circle")
                                                        .foregroundColor((selectedProductId == productDetails.productId) ? color : Color.primary.opacity(0.15))
                                                    
                                                    if selectedProductId == productDetails.productId {
                                                        Image(systemName: "checkmark")
                                                            .foregroundColor(Color.white)
                                                            .scaleEffect(0.7)
                                                    }
                                                }
                                                .font(.title3.bold())
                                                
                                            }
                                            .padding(.horizontal)
                                            .padding(.vertical, 10)
                                        }
                                        //.background(Color(.systemGray4))
                                        .cornerRadius(6)
                                        .overlay(
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke((selectedProductId == productDetails.productId) ? color : Color.primary.opacity(0.15), lineWidth: 1) // Border color and width
                                                RoundedRectangle(cornerRadius: 6)
                                                    .foregroundColor((selectedProductId == productDetails.productId) ? color.opacity(0.05) : Color.primary.opacity(0.001))
                                            }
                                        )
                                    }
                                    .accentColor(Color.primary)
                                    
                                }
                                
                                HStack {
                                    Toggle(isOn: $freeTrial) {
                                        Text(NSLocalizedString("free_trial_enabled", comment: "Free trial enabled"))
                                            .font(.headline.bold())
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                    .onChange(of: freeTrial) { freeTrial in
                                        if !freeTrial, let firstProductId = self.purchaseModel.productIds.first {
                                            withAnimation {
                                                self.selectedProductId = String(firstProductId)
                                            }
                                        }
                                        else if freeTrial, let lastProductId = self.purchaseModel.productIds.last {
                                            withAnimation {
                                                self.selectedProductId = lastProductId
                                            }
                                        }
                                    }
                                }
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(6)
                                
                            }
                            .opacity(purchaseModel.isFetchingProducts ? 0 : 1)
                            
                            VStack (spacing: 25) {
                                
                                ZStack (alignment: .center) {
                                    
                                    //if purchasedModel.isPurchasing {
                                    ProgressView()
                                        .opacity(purchaseModel.isPurchasing ? 1 : 0)
                                    
                                    Button(action: {
                                        //productManager.purchaseProduct()
                                        if !purchaseModel.isPurchasing {
                                            purchaseModel.purchaseSubscription(productId: self.selectedProductId)
                                        }
                                    }) {
                                        HStack {
                                            Spacer()
                                            HStack {
                                                Text(callToActionText)
                                                Image(systemName: "chevron.right")
                                            }
                                            Spacer()
                                        }
                                        .padding()
                                        .foregroundColor(.white)
                                        .font(.title3.bold())
                                    }
                                    .background(color)
                                    .cornerRadius(6)
                                    .opacity(purchaseModel.isPurchasing ? 0 : 1)
                                    .padding(.top)
                                    .padding(.bottom, 4)
                                    
                                    
                                }
                                
                            }
                            .opacity(purchaseModel.isFetchingProducts ? 0 : 1)
                        }
                        .id("view-\(purchaseModel.isFetchingProducts)")
                        .background {
                            if purchaseModel.isFetchingProducts {
                                ProgressView()
                            }
                        }
                        
                        VStack (spacing: 5) {
                            
                            /*HStack (spacing: 4) {
                                Image(systemName: "figure.2.and.child.holdinghands")
                                    .foregroundColor(Color.red)
                                Text(NSLocalizedString("family_sharing_enabled", comment: "Family sharing enabled"))
                                    .foregroundColor(.white)
                            }
                            .font(.footnote)*/
                            
                            HStack (spacing: 10) {
                                
                                Button(NSLocalizedString("restore_purchase", comment: "Restore purchase button")) {
                                    purchaseModel.restorePurchases()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                                        if !purchaseModel.isSubscribed {
                                            showNoneRestoredAlert = true
                                        }
                                    }
                                }
                                .alert(isPresented: $showNoneRestoredAlert) {
                                    Alert(title: Text(NSLocalizedString("restore_purchases", comment: "Restore purchases")), message: Text(NSLocalizedString("no_purchases_restored", comment: "No purchases restored")), dismissButton: .default(Text(NSLocalizedString("ok", comment: "OK button"))))
                                }
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.gray), alignment: .bottom
                                )
                                .font(.footnote)
                                
                                
                                Button(NSLocalizedString("terms_privacy_policy", comment: "Terms of use and privacy policy button")) {
                                    showTermsActionSheet = true
                                }
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.gray), alignment: .bottom
                                )
                                .actionSheet(isPresented: $showTermsActionSheet) {
                                    ActionSheet(title: Text(NSLocalizedString("view_terms_conditions", comment: "View terms and conditions")), message: nil,
                                                buttons: [
                                                    .default(Text(NSLocalizedString("terms_of_use", comment: "Terms of use")), action: {
                                                        if let url = URL(string: "https://coolappbox.com/terms") {
                                                            UIApplication.shared.open(url)
                                                        }
                                                    }),
                                                    .default(Text(NSLocalizedString("privacy_policy", comment: "Privacy policy")), action: {
                                                        if let url = URL(string: "https://coolappbox.com/privacy") {
                                                            UIApplication.shared.open(url)
                                                        }
                                                    }),
                                                    .cancel()
                                                ])
                                }
                                .font(.footnote)
                                
                                
                            }
                            //.font(.headline)
                            .foregroundColor(.gray)
                            .font(.system(size: 15))
                            
                            
                            
                            
                        }

                        
                    }
                }
                .padding(.horizontal)
            }
            .background(Color.white)
        }
        .padding(.horizontal)
        .onAppear {
            selectedProductId = purchaseModel.productIds.last ?? ""

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: allowCloseAfter)) {
                    self.progress = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + allowCloseAfter) {
                    withAnimation {
                        showCloseButton = true
                    }
                }
            }
        }
        .onChange(of: purchaseModel.isSubscribed) { isSubscribed in
            if isSubscribed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPresented = false
                }
            }
        }
        
        
    }
    
    private func startShaking() {
            let totalDuration = 0.7 // Total duration of the shake animation
            let numberOfShakes = 3 // Total number of shakes
            let initialAngle: Double = 10 // Initial rotation angle
            
            withAnimation(.easeInOut(duration: totalDuration / 2)) {
                self.shakeZoom = 0.95
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration / 2) {
                    withAnimation(.easeInOut(duration: totalDuration / 2)) {
                        self.shakeZoom = 0.9
                    }
                }
            }

            for i in 0..<numberOfShakes {
                let delay = (totalDuration / Double(numberOfShakes)) * Double(i)
                let angle = initialAngle - (initialAngle / Double(numberOfShakes)) * Double(i)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Animation.easeInOut(duration: totalDuration / Double(numberOfShakes * 2))) {
                        self.shakeDegrees = angle
                    }
                    withAnimation(Animation.easeInOut(duration: totalDuration / Double(numberOfShakes * 2)).delay(totalDuration / Double(numberOfShakes * 2))) {
                        self.shakeDegrees = -angle
                    }
                }
            }

            // Stop the shaking and reset to 0
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
                withAnimation {
                    self.shakeDegrees = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    startShaking()
                }
            }
        }
    
    
    struct PurchaseFeatureView: View {
        
        let title: String
        let icon: String
        let color: Color
        
        var body: some View {
            HStack {
                Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 27, height: 27, alignment: .center)
                .clipped()
                .foregroundColor(color)
                Text(title)
                    .foregroundColor(.black)
            }
        }
    }

    func toLocalCurrencyString(_ value: Double) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        //formatter.locale = locale
        return formatter.string(from: NSNumber(value: value))
    }

}

#Preview {
    PurchaseView(isPresented: .constant(true))
}
