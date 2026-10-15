import Foundation

/// Limit automatic restarts to three attempts; ten healthy seconds replenish the budget.
struct RecoveryPolicy {
    private(set) var attempts = 0
    private var nextAllowed = 0.0
    private var healthySince: Double?

    mutating func shouldRestart(now: Double, unhealthy: Bool, allowed: Bool) -> Bool {
        guard allowed else { healthySince = nil; return false }
        if !unhealthy {
            if healthySince == nil { healthySince = now }
            if now - (healthySince ?? now) >= 10 { attempts = 0; nextAllowed = 0 }
            return false
        }
        healthySince = nil
        guard attempts < 3 && now >= nextAllowed else { return false }
        attempts += 1
        nextAllowed = now + 5 * pow(2, Double(attempts - 1))
        return true
    }
}
