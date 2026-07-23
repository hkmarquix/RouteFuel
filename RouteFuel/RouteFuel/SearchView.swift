import SwiftUI
import MapKit

struct SearchView: View {
    @ObservedObject var viewModel: RoutePlannerViewModel
    @FocusState private var isSearchFieldFocused: Bool

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
                    Color.black.opacity(0.58),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.32)
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
                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)

            Text("Select a start, pick a destination, then calculate the route.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .shadow(color: Color.black.opacity(0.28), radius: 6, y: 3)

            plannerCard
        }
    }

    private var plannerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FROM row
            Button {
                viewModel.activateSearchTarget(.origin)
            } label: {
                selectionRow(
                    title: "From",
                    value: viewModel.originUsesCurrentLocation ? "Current location" : (viewModel.selectedOrigin?.label ?? "Select a start"),
                    detail: viewModel.originUsesCurrentLocation ? "Current location selected" : (viewModel.selectedOrigin == nil ? "Tap to search or use current location" : "Custom start selected"),
                    isSelected: viewModel.originUsesCurrentLocation || viewModel.selectedOrigin != nil
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("from-row-button")
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Origin search — shown inline under FROM
            if viewModel.activeSearchTarget == .origin {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        viewModel.selectCurrentLocation()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.caption.weight(.semibold))
                            Text("Use Current Location")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.31))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("use-current-location-button")

                    HStack(spacing: 10) {
                        TextField("Search a starting location", text: originQueryBinding)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($isSearchFieldFocused)
                            .onSubmit { Task { await viewModel.submitOriginSearch() } }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("origin-query-field")

                        Button("Search From") {
                            isSearchFieldFocused = false
                            Task { await viewModel.submitOriginSearch() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.12, green: 0.43, blue: 0.31))
                        .disabled(!canSubmitOriginSearch)
                        .accessibilityIdentifier("origin-search-button")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Divider()
                .overlay(Color.black.opacity(0.08))
                .padding(.horizontal, 16)

            // TO row
            Button {
                viewModel.activateSearchTarget(.destination)
            } label: {
                selectionRow(
                    title: "To",
                    value: viewModel.selectedDestination?.label ?? "Select a destination",
                    detail: viewModel.selectedDestination == nil ? "Tap to search for a destination" : "Destination selected",
                    isSelected: viewModel.selectedDestination != nil
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, viewModel.activeSearchTarget == .destination ? 10 : 16)

            // Destination search — shown inline under TO
            if viewModel.activeSearchTarget == .destination {
                HStack(spacing: 10) {
                    TextField("Search a United Kingdom destination", text: destinationQueryBinding)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isSearchFieldFocused)
                        .onSubmit { Task { await viewModel.submitDestinationSearch() } }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("destination-query-field")

                    Button("Search To") {
                        isSearchFieldFocused = false
                        Task { await viewModel.submitDestinationSearch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.12, green: 0.43, blue: 0.31))
                    .disabled(!canSubmitDestinationSearch)
                    .accessibilityIdentifier("destination-search-button")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Divider()
                .overlay(Color.black.opacity(0.08))

            Button("Calculate Route") {
                Task { await viewModel.calculateRoute() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canCalculateRoute)
            .accessibilityIdentifier("calculate-route-button")
            .padding(16)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func selectionRow(title: String, value: String, detail: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isSelected ? Color.green : Color.black.opacity(0.16))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                            isSearchFieldFocused = false
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

    private var originQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.originQuery },
            set: { viewModel.originQueryChanged($0) }
        )
    }

    private var destinationQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.destinationQuery },
            set: { viewModel.destinationQueryChanged($0) }
        )
    }

    private var canSubmitOriginSearch: Bool {
        !viewModel.originQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.destinationSearchLoading
    }

    private var canSubmitDestinationSearch: Bool {
        !viewModel.destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.destinationSearchLoading
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(Color(.systemBackground).opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 18, y: 8)
    }
}
