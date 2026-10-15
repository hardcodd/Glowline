import Foundation

func runRecoveryTests() {
    var policy = RecoveryPolicy()
    precondition(!policy.shouldRestart(now: 0, unhealthy: true, allowed: false))
    precondition(policy.shouldRestart(now: 0, unhealthy: true, allowed: true))
    precondition(!policy.shouldRestart(now: 4.9, unhealthy: true, allowed: true))
    precondition(policy.shouldRestart(now: 5, unhealthy: true, allowed: true))
    precondition(!policy.shouldRestart(now: 14.9, unhealthy: true, allowed: true))
    precondition(policy.shouldRestart(now: 15, unhealthy: true, allowed: true))
    precondition(!policy.shouldRestart(now: 100, unhealthy: true, allowed: true))
    precondition(!policy.shouldRestart(now: 101, unhealthy: false, allowed: true))
    precondition(!policy.shouldRestart(now: 110, unhealthy: false, allowed: true))
    precondition(policy.attempts == 3)
    precondition(!policy.shouldRestart(now: 111, unhealthy: false, allowed: true))
    precondition(policy.attempts == 0)
    precondition(policy.shouldRestart(now: 112, unhealthy: true, allowed: true))
    print("Bounded recovery contracts passed")
}
