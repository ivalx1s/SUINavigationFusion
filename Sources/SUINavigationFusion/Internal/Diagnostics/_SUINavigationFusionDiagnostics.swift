import Foundation

enum _SUINavigationFusionDiagnostics {
    static func isZoomEnabled() -> Bool {
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["SUINAV_ZOOM_DIAGNOSTICS"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return raw == "1" || raw == "true" || raw == "yes"
        }
        if UserDefaults.standard.bool(forKey: "SUINAV_ZOOM_DIAGNOSTICS") {
            return true
        }
        return false
#else
        return false
#endif
    }

    static func zoom(_ message: @autoclosure () -> String) {
        guard isZoomEnabled() else { return }
        let ts = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
        print("[SUINavigationFusion][ZoomDiag][\(ts)] \(message())")
    }
}
