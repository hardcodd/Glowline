#pragma once

namespace glowline {
// One initial attempt and three recoveries, replenished only by ten healthy seconds.
class RecoveryBudget {
    unsigned failures_ = 0;
    double next_ = 0, healthy_since_ = -1;

  public:
    void reset() {
        failures_ = 0;
        next_ = 0;
        healthy_since_ = -1;
    }
    bool ready(double now, bool reconnect = true) const {
        return failures_ < 4 && now >= next_ && (failures_ == 0 || reconnect);
    }
    void failed(double now) {
        healthy_since_ = -1;
        if (failures_ < 4) {
            next_ = now + 5 * (1u << failures_);
            failures_++;
        }
    }
    void healthy(double now) {
        if (healthy_since_ < 0)
            healthy_since_ = now;
        if (now - healthy_since_ >= 10) {
            failures_ = 0;
            next_ = 0;
        }
    }
};
} // namespace glowline
