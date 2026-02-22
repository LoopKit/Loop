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
        isResolving = false
    }

    /// Returns a prompt snippet with restaurant/location context for the AI,
    /// or an empty string if no location is available.
    func locationContextForPrompt() -> String {
        guard FoodFinder_FeatureFlags.locationTaggingEnabled,
              let name = locationName, !name.isEmpty else {
            return ""
        }

        return """

        LOCATION CONTEXT: The user is currently at or near "\(name)".
        If you can identify specific menu items from this restaurant or establishment, use known nutrition facts from their published menu data for more accurate carbohydrate and macro estimates.
        Mention the restaurant name in your response if it's relevant to the analysis.
        """
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

                // Prefer the business/POI name, fall back to thoroughfare
                if let placemark = placemarks?.first {
                    let name = placemark.name
                        ?? placemark.areasOfInterest?.first
                        ?? placemark.thoroughfare
                    self.locationName = name
                    #if DEBUG
                    print("📍 FoodFinder Location: \(name ?? "unknown") (\(self.latitude ?? 0), \(self.longitude ?? 0))")
                    #endif
                }
                self.isResolving = false
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
