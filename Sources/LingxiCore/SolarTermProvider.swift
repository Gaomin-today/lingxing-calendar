import Foundation

/// One shared, immutable-per-year cache keeps repeated SwiftUI chart reads from
/// recalculating astronomy. NSLock serializes both publication and computation.
internal final class NativeSolarTermProvider: @unchecked Sendable {
    static let shared = NativeSolarTermProvider()
    private let lock = NSLock()
    private var cachedYears: [Int: [SolarTermBoundary]] = [:]

    private init() {}

    func terms(in year: Int) throws -> [SolarTermBoundary] {
        // Padding years serve early/late dates at the documented public edges.
        guard (1900...2100).contains(year) else { throw FourPillarsError.unsupportedYear }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedYears[year] { return cached }
        let terms = (0..<24).map { index -> SolarTermBoundary in
            // The unwrapped apparent solar longitude is 285° at 小寒 2000;
            // each following term advances 15°, and each year adds 360°.
            let longitude = (Double(year - 2000) * 24 + Double(index) + 19) * Double.pi / 12
            // qiAccurate returns days since J2000 expressed in Beijing time.
            // Remove its fixed +8-hour shift before converting to a UTC Date.
            let beijingDays = ShouXingSolar.qiAccurate(w: longitude)
            let unixSeconds = (beijingDays + 2451545.0 - 2440587.5 - 1.0 / 3.0) * 86400
            return SolarTermBoundary(index: index, date: Date(timeIntervalSince1970: unixSeconds))
        }
        cachedYears[year] = terms
        return terms
    }
}
