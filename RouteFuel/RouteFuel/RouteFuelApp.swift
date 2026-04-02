//
//  RouteFuelApp.swift
//  RouteFuel
//
//  Created by Siu Lun Corley Chan on 1/4/2026.
//

import SwiftUI

@main
struct RouteFuelApp: App {
    private let dependencies = AppDependencies.bootstrap()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: RoutePlannerViewModel(dependencies: dependencies))
        }
    }
}
