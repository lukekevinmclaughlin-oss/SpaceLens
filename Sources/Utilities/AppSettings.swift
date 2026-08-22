import Foundation
import Combine

/// User-tunable thresholds for the smart finders, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var oldFileDays: Int { didSet { d.set(oldFileDays, forKey: "oldFileDays") } }
    @Published var oldFileMinMB: Int { didSet { d.set(oldFileMinMB, forKey: "oldFileMinMB") } }
    @Published var duplicateMinMB: Int { didSet { d.set(duplicateMinMB, forKey: "duplicateMinMB") } }
    @Published var devJunkEnabled: Bool { didSet { d.set(devJunkEnabled, forKey: "devJunkEnabled") } }
    @Published var menuBarEnabled: Bool { didSet { d.set(menuBarEnabled, forKey: "menuBarEnabled") } }
    @Published var lowSpacePercent: Int { didSet { d.set(lowSpacePercent, forKey: "lowSpacePercent") } }

    private let d = UserDefaults.standard

    private init() {
        oldFileDays    = d.object(forKey: "oldFileDays")    as? Int ?? 365
        oldFileMinMB   = d.object(forKey: "oldFileMinMB")   as? Int ?? 5
        duplicateMinMB = d.object(forKey: "duplicateMinMB") as? Int ?? 1
        devJunkEnabled = d.object(forKey: "devJunkEnabled") as? Bool ?? true
        menuBarEnabled = d.object(forKey: "menuBarEnabled") as? Bool ?? true
        lowSpacePercent = d.object(forKey: "lowSpacePercent") as? Int ?? 10
    }
}
