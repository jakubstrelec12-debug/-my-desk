import Foundation
import CoreLocation

@MainActor final class CurrentLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<WeatherLocation, Error>?
    private var timeout: Task<Void, Never>?
    private var requestID = UUID()
    private var cached: WeatherLocation?
    private var cachedAt = Date.distantPast
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    func locate() async throws -> WeatherLocation {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            throw DeskError("Poloha je vypnutá. Povol MY DESK v Nastavení systému → Soukromí a zabezpečení → Polohové služby.")
        }
        if status != .notDetermined, let cached, Date().timeIntervalSince(cachedAt) < 900 { return cached }
        guard pending == nil else { throw DeskError("Zjišťování polohy už probíhá.") }
        requestID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 35_000_000_000) } catch { return }
                self?.finish(.failure(DeskError("Polohu Macu se nepodařilo včas zjistit. Zkontroluj Polohové služby a zapnutou Wi-Fi.")))
            }
            if status == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { manager.requestLocation() }
        }
    }
    private func finish(_ result: Result<WeatherLocation, Error>) {
        guard let continuation = pending else { return }
        pending = nil; timeout?.cancel(); timeout = nil; manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.pending != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(.failure(DeskError("Přístup k poloze není povolený. Použij uložené město nebo povol Polohové služby pro MY DESK.")))
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.pending != nil, let location = locations.last,
                  location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 600 else { return }
            let id = self.requestID
            let places = try? await CLGeocoder().reverseGeocodeLocation(location)
            guard self.pending != nil, id == self.requestID else { return }
            let place = places?.first
            let name = place?.locality ?? place?.subAdministrativeArea ?? "Aktuální poloha"
            let found = WeatherLocation(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            self.cached = found; self.cachedAt = Date()
            self.finish(.success(found))
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(.failure(DeskError("Polohu se nepodařilo zjistit. Zkontroluj zapnutou Wi-Fi a Polohové služby macOS.")))
        }
    }
}
