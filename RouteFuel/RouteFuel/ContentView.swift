//
//  ContentView.swift
//  RouteFuel
//
//  Created by Siu Lun Corley Chan on 1/4/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: RoutePlannerViewModel

    init(viewModel: RoutePlannerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let trip = viewModel.tripPlan {
                    ResultsView(viewModel: viewModel, trip: trip)
                } else {
                    SearchView(viewModel: viewModel)
                }
            }
            .animation(.snappy, value: viewModel.tripPlan?.route.id)
        }
    }
}
