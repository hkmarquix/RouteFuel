import SwiftUI
import MapKit

struct SearchView: View {
    @ObservedObject var viewModel: RoutePlannerViewModel

    var body: some View {
        ZStack(alignment: .top) {
            SearchResultsMap(
                results: viewModel.visibleSearchResults,
                selectedResult: viewModel.selectedSearchResult,
                onSelect: viewModel.selectSearchResult
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top) {
            topPanel
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            bottomPanel
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationBarHidden(true)
    }

    private var topPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RouteFuel")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Select a start, pick a destination, then calculate the route.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))

            plannerCard
        }
    }

    private var plannerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            routeSelectionCard

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.activeSearchTarget == .origin ? "Search Start" : "Search Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 10) {
                    TextField(
                        viewModel.activeSearchTarget == .origin ? "Search a starting location" : "Search a United Kingdom destination",
                        text: activeQueryBinding
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier(viewModel.activeSearchTarget == .origin ? "origin-query-field" : "destination-query-field")

                    Button(viewModel.activeSearchTarget == .origin ? "Search From" : "Search To") {
                        switch viewModel.activeSearchTarget {
                        case .origin:
                            Task { await viewModel.submitOriginSearch() }
                        case .destination:
                            Task { await viewModel.submitDestinationSearch() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.12, green: 0.43, blue: 0.31))
                    .disabled(!canSearchActiveTarget)
                }
            }

            Button("Calculate Route") {
                Task { await viewModel.calculateRoute() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canCalculateRoute)
            .accessibilityIdentifier("calculate-route-button")
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var routeSelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                viewModel.activateSearchTarget(.origin)
                viewModel.selectCurrentLocation()
            } label: {
                selectionRow(
                    title: "From",
                    value: viewModel.originUsesCurrentLocation ? "Current location" : (viewModel.selectedOrigin?.label ?? "Select a start"),
                    detail: viewModel.originUsesCurrentLocation ? "Selected start point" : (viewModel.selectedOrigin == nil ? "Search and select a start location" : "Custom start selected"),
                    isSelected: viewModel.originUsesCurrentLocation || viewModel.selectedOrigin != nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("origin-current-location-button")

            Divider()
                .overlay(Color.white.opacity(0.16))

            Button {
                viewModel.activateSearchTarget(.destination)
            } label: {
                selectionRow(
                    title: "To",
                    value: viewModel.selectedDestination?.label ?? "Select a destination",
                    detail: viewModel.selectedDestination == nil ? "Search and select a destination" : "Destination selected",
                    isSelected: viewModel.selectedDestination != nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func selectionRow(title: String, value: String, detail: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isSelected ? Color.green : Color.white.opacity(0.28))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))

                Text(value)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = viewModel.blockingMessage {
                BlockingMessageCard(message: message) {
                    Task { await viewModel.retry() }
                }
            } else if viewModel.routeLoading {
                statusCard("Calculating route...")
            } else if viewModel.destinationSearchLoading {
                statusCard("Searching destinations...")
            } else if viewModel.zeroResultsVisible {
                BlockingMessageCard(
                    message: .init(
                        title: "No destinations found",
                        body: "Try a different search.",
                        retryAction: nil
                    ),
                    retry: nil
                )
            } else if !viewModel.visibleSearchResults.isEmpty {
                destinationResultsCard
            } else {
                hintCard
            }
        }
    }

    private var destinationResultsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.activeSearchTarget == .origin ? "Start Results" : "Destination Results")
                .font(.headline)

            Text(viewModel.activeSearchTarget == .origin ? "Tap a pin or a result to choose the start location." : "Tap a pin or a result to choose the destination.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.visibleSearchResults) { result in
                        Button {
                            viewModel.selectSearchResult(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.label)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)

                                Text(viewModel.selectedSearchResult == result ? "Selected" : "Tap to select")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(viewModel.selectedSearchResult == result ? Color.green : .secondary)
                            }
                            .padding(16)
                            .frame(width: 220, alignment: .leading)
                            .background(
                                viewModel.selectedSearchResult == result ? Color.green.opacity(0.14) : Color(.systemBackground).opacity(0.92),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("destination-result-\(result.label)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .panelStyle()
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Map-first search")
                .font(.headline)

            Text("Tap `From` or `To`, search for that leg, select a result, then calculate the route.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var activeQueryBinding: Binding<String> {
        Binding(
            get: {
                viewModel.activeSearchTarget == .origin ? viewModel.originQuery : viewModel.destinationQuery
            },
            set: { newValue in
                switch viewModel.activeSearchTarget {
                case .origin:
                    viewModel.originQueryChanged(newValue)
                case .destination:
                    viewModel.destinationQueryChanged(newValue)
                }
            }
        )
    }

    private var canSearchActiveTarget: Bool {
        let query = viewModel.activeSearchTarget == .origin ? viewModel.originQuery : viewModel.destinationQuery
        return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.destinationSearchLoading
    }

    private func statusCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct SearchResultsMap: View {
    let results: [DestinationSearchResult]
    let selectedResult: DestinationSearchResult?
    let onSelect: (DestinationSearchResult) -> Void

    @State private var position = MapCameraPosition.region(Self.defaultRegion)
    @State private var selectedMarker: DestinationSearchResult?

    var body: some View {
        Map(position: $position, selection: $selectedMarker) {
            ForEach(results) { result in
                Marker(result.label, coordinate: result.coordinate.locationCoordinate)
                    .tint(result == selectedResult ? .green : .red)
                    .tag(result)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            syncMapToResults()
            selectedMarker = selectedResult
        }
        .onChange(of: results) { _, _ in
            syncMapToResults()
        }
        .onChange(of: selectedResult) { _, newValue in
            selectedMarker = newValue
            guard let newValue else { return }
            position = .region(Self.region(for: [newValue.coordinate]))
        }
        .onChange(of: selectedMarker) { _, newValue in
            guard let newValue else { return }
            onSelect(newValue)
        }
        .accessibilityIdentifier("destination-search-map")
    }

    private func syncMapToResults() {
        if let selectedResult {
            position = .region(Self.region(for: [selectedResult.coordinate]))
        } else {
            position = .region(Self.region(for: results.map(\.coordinate)))
        }
    }

    private static func region(for points: [Coordinate]) -> MKCoordinateRegion {
        guard !points.isEmpty else { return defaultRegion }
        return RouteMapViewport.region(for: points)
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.5, longitude: -3.0),
        span: MKCoordinateSpan(latitudeDelta: 8.5, longitudeDelta: 8.5)
    )
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
