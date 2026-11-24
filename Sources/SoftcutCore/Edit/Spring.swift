import Foundation

/// A damped spring that chases a moving target. Stepped at a fixed rate so the
/// result is deterministic and can be sampled again for any frame.
struct Spring {
    var stiffness: Double
    var damping: Double
    var mass: Double
    var value: Double
    var velocity = 0.0
    /// Stop on the target instead of swinging past it. A lightly damped spring that is clamped moves briskly
    /// and lands without a bounce.
    var clamp = false

    /// The motion used for both the cursor and the camera: critically damped, easing into place in about 0.4 s with
    /// no overshoot. Measured from Screen Studio's output frame by frame (its settings call this stiffness 125,
    /// damping 12, mass 1.5, but the motion it produces is this).
    static let standard = (stiffness: 144.0, damping: 24.0, mass: 1.0)

    init(value: Double, stiffness: Double, damping: Double, mass: Double, clamp: Bool = false) {
        self.value = value
        self.stiffness = stiffness
        self.damping = damping
        self.mass = mass
        self.clamp = clamp
    }

    static func standard(_ value: Double) -> Spring {
        Spring(value: value, stiffness: standard.stiffness, damping: standard.damping, mass: standard.mass)
    }

    mutating func step(toward target: Double, dt: Double) {
        // Semi-implicit Euler, split into small sub-steps so stiff springs stay stable.
        let substeps = max(1, Int((dt / 0.002).rounded(.up)))
        let h = dt / Double(substeps)
        for _ in 0..<substeps {
            let before = value - target
            let force = stiffness * (target - value) - damping * velocity
            velocity += force / mass * h
            value += velocity * h
            if clamp, before != 0, (value - target) * before <= 0 {
                value = target
                velocity = 0
            }
        }
    }
}

/// A fixed-rate series of values that can be read at any time with linear interpolation.
struct SampledTrack<Value> {
    let rate: Double
    var samples: [Value]

    func index(at time: Double) -> (Int, Double) {
        let position = max(0, time) * rate
        let lower = min(Int(position), samples.count - 1)
        let upper = min(lower + 1, samples.count - 1)
        return (lower, upper == lower ? 0 : position - Double(lower))
    }
}
