//
//  OnboardingView.swift
//
//  Created by Adam Lyttle on 2/5/2023.
//
//  adamlyttleapps.com
//  twitter.com/adamlyttleapps
//
//  Usage example available in ContentView.swift

import SwiftUI

struct Feature: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String?
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    let appName: String
    let features: [Feature]
    let color: Color?
    let onboardingCompleted: () -> Void
    
    var body: some View {
        VStack {
            Text(String(format: NSLocalizedString("welcome_to_app", comment: "Welcome message"), appName))
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.vertical, 50)
                .multilineTextAlignment(.center)
            Spacer()
            VStack {
                ForEach(features) { feature in
                    VStack(alignment: .leading) {
                        HStack {
                            if let icon = feature.icon {
                                Image(systemName: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 45, alignment: .center)
                                    .clipped()
                                    .foregroundColor(color ?? Color.blue)
                                    .padding(.trailing, 15)
                                    .padding(.vertical, 10)
                            }
                            VStack(alignment: .leading) {
                                Text(feature.title)
                                    .fontWeight(.bold)
                                    .font(.system(size: 16))
                                Text(feature.description)
                                    .font(.system(size: 15))
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal,20)
                    .padding(.bottom, 20)
                }
            }
            .padding(.bottom, 30)
            Spacer()
            VStack {
                Button(action: {
                    UserDefaults.standard.set(true, forKey: "OnboardingSeen")
                    dismiss()
                    onboardingCompleted()
                }) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(color ?? Color.blue)
                            .cornerRadius(12)
                            .frame(height: 54)
                        Text(NSLocalizedString("continue_button", comment: "Continue button"))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.top, 15)
            .padding(.bottom, 50)
            .padding(.horizontal,15)
        }
        .padding()
        .background(Color.white)
        .edgesIgnoringSafeArea(.all) // 确保背景延伸到边缘
    }
}
