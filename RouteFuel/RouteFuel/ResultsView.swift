import MapKit
import SwiftUI

struct ResultsView: View {
    @ObservedObject var viewModel: RoutePlannerViewModel
    let trip: TripPlan

    var body: some View {
        ZStack(alignment: .topLeading) {
            RouteMapCard(route: trip.route, selectedStop: trip.selectedStop)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.52),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.3)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            bottomSheet
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .navigationBarHidden(true)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button("Back") {
                viewModel.resetTrip()
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.72))

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(trip.route.destination.label)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)

                Text("\(trip.route.distanceText) • \(trip.route.durationText)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
                    .shadow(color: Color.black.opacity(0.28), radius: 6, y: 3)
            }
        }
    }

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = viewModel.blockingMessage {
                BlockingMessageCard(message: message) {
                    Task { await viewModel.retry() }
                }
            }

            if viewModel.recommendationsLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding fuel stops...")
                        .foregroundStyle(.secondary)
                }
                .panelStyle()
            } else {
                recommendationsPanel
            }

            if trip.selectedStop != nil {
                HStack(spacing: 12) {
                    Button("Open in Apple Maps") {
                        Task { await viewModel.openInAppleMaps() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(viewModel.appleMapsOpening || viewModel.googleMapsOpening)
                    .accessibilityIdentifier("open-apple-maps-button")

                    if viewModel.canOpenGoogleMaps {
                        Button("Open in Google Maps") {
                            Task { await viewModel.openInGoogleMaps() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.12, green: 0.43, blue: 0.31))
                        .disabled(viewModel.appleMapsOpening || viewModel.googleMapsOpening)
                        .accessibilityIdentifier("open-google-maps-button")
                    }
                }
            }
        }
    }

    private var recommendationsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fuel Stops")
                .font(.headline)

            if trip.recommendedStops.isEmpty {
                Text("No recommendations are visible right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(trip.recommendedStops) { stop in
                            Button {
                                viewModel.selectStop(stop)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        Text(stop.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(2)

                                        Spacer(minLength: 8)

                                        if stop.isBestStop {
                                            Text("Best Stop")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.green.opacity(0.18), in: Capsule())
                                        }
                                    }

                                    Text(stop.address)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    Text("\(stop.priceText) • \(stop.detourText)")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Text(trip.selectedStop == stop ? "Selected • Rank #\(stop.rank)" : "Tap to select • Rank #\(stop.rank)")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(trip.selectedStop == stop ? Color.green : .secondary)
                                }
                                .padding(16)
                                .frame(width: 250, alignment: .leading)
                                .background(
                                    trip.selectedStop == stop ? Color.green.opacity(0.14) : Color(.systemBackground).opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .panelStyle()
    }
}

struct RouteMapViewport {
    static func region(for points: [Coordinate]) -> MKCoordinateRegion {
        guard !points.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 54.5, longitude: -3.0),
                span: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 8.0)
            )
        }

        let latitudes = points.map(\.lat)
        let longitudes = points.map(\.lng)

        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 0
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 0

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.35, 0.05),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.35, 0.05)
            )
        )
    }
}

private struct RouteMapCard: View {
    let route: Route
    let selectedStop: FuelStop?
    @State private var position: MapCameraPosition

    init(route: Route, selectedStop: FuelStop?) {
        self.route = route
        self.selectedStop = selectedStop
        _position = State(initialValue: .region(RouteMapViewport.region(for: route.path)))
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: route.path.map(\.locationCoordinate))
                .stroke(Color(red: 0.09, green: 0.48, blue: 0.95), lineWidth: 6)

            Annotation("Origin", coordinate: route.origin.locationCoordinate) {
                mapBadge("Origin", color: .black)
            }

            Annotation(route.destination.label, coordinate: route.destination.coordinate.locationCoordinate) {
                mapBadge("Destination", color: .blue)
            }

            ForEach(routeStops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate.locationCoordinate) {
                    mapBadge(stop.isBestStop ? "Best" : "#\(stop.rank)", color: stop == selectedStop ? .green : .orange)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onChange(of: selectedStop) { _, newValue in
            guard let newValue else {
                position = .region(RouteMapViewport.region(for: route.path))
                return
            }

            position = .region(Self.region(focusedOn: newValue.coordinate))
        }
        .accessibilityIdentifier("route-map")
    }

    private var routeStops: [FuelStop] {
        if let selectedStop {
            return [selectedStop]
        }
        return []
    }

    private func mapBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color, in: Capsule())
    }

    private static func region(focusedOn coordinate: Coordinate) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate.locationCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
        )
    }
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
