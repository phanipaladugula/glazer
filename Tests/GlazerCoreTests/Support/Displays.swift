@testable import GlazerCore

/// A MacBook straight ahead and a monitor to the right.
let macBookID: Display.ID = 1
let monitorID: Display.ID = 2
let twoDisplayCalibration = Calibration(points: [
    .init(displayID: macBookID, pose: HeadPose(yaw: -4, pitch: -8)),
    .init(displayID: monitorID, pose: HeadPose(yaw: 28, pitch: 2)),
])
