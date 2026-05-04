//
//  FoodFinder_LocationService.swift
//  Loop
//
//  FoodFinder — One-shot GPS capture + reverse geocode for meal location tagging.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit
import Combine
import os.log

/// Captures venue-level location when FoodFinder opens, reverse-geocodes it to a
/// restaurant/business name, and provides prompt context for the AI analysis.
///
/// Privacy-first design:
/// - Feature off by default; only requests permission after user enables toggle
/// - One-shot `requestLocation()` — not continuous tracking
/// - `kCLLocationAccuracyHundredMeters` — venue-level, not GPS-precise
/// - Data local-only — coordinates never leave the device
final class FoodFinder_LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Singleton

    static let shared = FoodFinder_LocationService()

    // MARK: - Published State

    @Published private(set) var latitude: Double?
    @Published private(set) var longitude: Double?
    @Published private(set) var locationName: String?
    @Published private(set) var cityName: String?
    @Published private(set) var countryName: String?
    @Published private(set) var isResolving: Bool = false

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let log = OSLog(category: "FoodFinder_Location")

    // MARK: - Init

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public API

    /// Requests a one-shot location fix if the feature flag is enabled and
    /// the user has granted (or not yet denied) location permission.
    /// Called from `FoodFinder_EntryPoint.onAppear`.
    func requestLocationIfEnabled() {
        guard FoodFinder_FeatureFlags.locationTaggingEnabled else { return }

        // Skip if we already have a resolved location or are currently resolving
        guard locationName == nil && cityName == nil && !isResolving else { return }

        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginLocationRequest()
        case .denied, .restricted:
            os_log("Location permission denied/restricted — skipping", log: log, type: .info)
        @unknown default:
            break
        }
    }

    /// Clears captured location data. Call when FoodFinder is dismissed.
    func clearLocation() {
        latitude = nil
        longitude = nil
        locationName = nil
        cityName = nil
        countryName = nil
        isResolving = false
    }

    /// Returns a prompt snippet with restaurant/location context for the AI,
    /// or an empty string if no location is available.
    func locationContextForPrompt() -> String {
        guard FoodFinder_FeatureFlags.locationTaggingEnabled else { return "" }

        // Build region string (e.g. "Athens, Greece") even if venue name is missing
        var regionParts: [String] = []
        if let city = cityName, !city.isEmpty { regionParts.append(city) }
        if let country = countryName, !country.isEmpty { regionParts.append(country) }
        let region = regionParts.isEmpty ? nil : regionParts.joined(separator: ", ")

        let venueName = (locationName?.isEmpty == false) ? locationName : nil

        // Need at least one piece of location info
        guard venueName != nil || region != nil else { return "" }

        var ctx = "\n\nLOCATION CONTEXT:\n"

        if let venue = venueName, let reg = region {
            ctx += "The user's GPS places them at or near \"\(venue)\" in \(reg).\n"
        } else if let venue = venueName {
            ctx += "The user's GPS places them at or near \"\(venue)\".\n"
        } else if let reg = region {
            ctx += "The user's GPS places them in \(reg).\n"
        }

        ctx += """
        Use this location to improve your analysis:
        1. REGIONAL CUISINE: Identify the food using local/regional dish names and preparation styles \
        typical of this area. A pastry in Athens is more likely tiropita or bougatsa than a generic phyllo roll.
        2. RESTAURANT MATCH: If the GPS venue name matches a known restaurant, reference their menu \
        for more accurate nutrition data instead of generic USDA values.
        3. CROSS-REFERENCE: Also look for restaurant names, logos, or branding visible in the image \
        (on napkins, plates, menus, receipts, signage). If you find a name that matches or confirms \
        the GPS location, use that restaurant's known menu items for identification and nutrition.
        4. TITLE FORMAT: Include the restaurant/venue name in the food title, e.g.: \
        "Carne Asada (grilled) – Casa de Bandini" so the user can see where it came from at a glance.
        5. LOCATION NOTE: Begin your "diabetes_considerations" field with a brief location line, e.g.: \
        "📍 \(buildLocationLabel()). " \
        Then continue with your normal diabetes guidance.
        """

        return ctx
    }

    /// Builds a compact label like "Ciel, Athens, Greece" or "Athens, Greece".
    private func buildLocationLabel() -> String {
        var parts: [String] = []
        if let name = locationName, !name.isEmpty { parts.append(name) }
        if let city = cityName, !city.isEmpty, city != locationName { parts.append(city) }
        if let country = countryName, !country.isEmpty { parts.append(country) }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: ", ")
    }

    // MARK: - Private Helpers

    private func beginLocationRequest() {
        isResolving = true
        locationManager.requestLocation()
    }

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    os_log("Reverse geocode failed: %{public}@", log: self.log, type: .error, error.localizedDescription)
                    self.isResolving = false
                    return
                }

                // Only use venue/POI names — skip bare street addresses
                if let placemark = placemarks?.first {
                    var name = placemark.name ?? placemark.areasOfInterest?.first

                    // CoreLocation sometimes returns a street address as `name`
                    // when there's no POI — discard it so we don't send
                    // meaningless addresses to the AI prompt.
                    if let n = name, let street = placemark.thoroughfare, n == street {
                        name = nil
                    }
                    // Also discard if name looks like a street number + name pattern
                    // (e.g. "1234 Oak Ave") with no business context
                    if let n = name, let street = placemark.thoroughfare,
                       n.hasPrefix(street) || n.hasSuffix(street) {
                        name = nil
                    }

                    self.locationName = name
                    self.cityName = placemark.locality
                    self.countryName = placemark.country
                    #if DEBUG
                    print("📍 FoodFinder Geocode: \(name ?? "unknown"), \(placemark.locality ?? "?"), \(placemark.country ?? "?") (\(self.latitude ?? 0), \(self.longitude ?? 0))")
                    #endif
                }

                // Refine with MapKit local search for nearby restaurants/food venues
                self.searchNearbyFoodVenues(location)
            }
        }
    }

    /// Uses MKLocalSearch to find the closest restaurant/food venue within 100m.
    /// If found, replaces the generic geocode name (often a shopping center) with
    /// the specific restaurant name.
    private func searchNearbyFoodVenues(_ location: CLLocation) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 100,
            longitudinalMeters: 100
        )
        request.resultTypes = .pointOfInterest

        MKLocalSearch(request: request).start { [weak self] response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                defer { self.isResolving = false }

                guard let items = response?.mapItems, !items.isEmpty else {
                    #if DEBUG
                    print("📍 FoodFinder MapKit: no nearby restaurants found")
                    #endif
                    return
                }

                // Find the closest food venue by distance
                let closest = items
                    .compactMap { item -> (name: String, distance: CLLocationDistance)? in
                        guard let name = item.name, !name.isEmpty else { return nil }
                        let dist = location.distance(from: MKMapItem.forCurrentLocation().placemark.location ?? location)
                        let itemLoc = CLLocation(latitude: item.placemark.coordinate.latitude,
                                                 longitude: item.placemark.coordinate.longitude)
                        return (name, location.distance(from: itemLoc))
                    }
                    .sorted { $0.distance < $1.distance }
                    .first

                if let match = closest {
                    // Only replace if the MapKit result is different from the geocode result
                    if self.locationName != match.name {
                        #if DEBUG
                        print("📍 FoodFinder MapKit: refined \"\(self.locationName ?? "nil")\" → \"\(match.name)\" (\(Int(match.distance))m away)")
                        #endif
                        self.locationName = match.name
                    }
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        os_log("Location request failed: %{public}@", log: log, type: .error, error.localizedDescription)
        isResolving = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // If the user just granted permission (from the .notDetermined prompt),
        // proceed with the location request.
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            beginLocationRequest()
        }
    }
}
