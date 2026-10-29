// A live check of the camera and Vision, using the same code Glazer runs.
//
//   swift run glazer-camera-check
//
// It prints the number of faces in view, the nearest face's head yaw and pitch, and the
// light level, several times a second. Turn your head from one display to the other: the
// yaw should change smoothly by 20 degrees or more. Press Ctrl-C to stop. Nothing is
// recorded or saved.
//
//   swift run glazer-camera-check --hands
//
// Also reads the nearest hand: its shape measures (reach, curl, spread) and how open it
// is, from 0% (fist) to 100% (open), by the hand calibration saved in Glazer if there is
// one, otherwise by a typical hand. Open and close your hand: the two should be far apart.
//
// macOS asks for camera access the first time, for the app this runs in (such as Terminal).

import AppKit
import GlazerCore
import GlazerSystem

@MainActor
final class CameraCheck {
    private let camera = CameraFeed()
    private var filter = HeadPoseFilter()
    private var lightMeter = LightMeter()
    private var tracker = UserTracker()
    private var lastPrint = 0.0
    private var yawRange: ClosedRange<Double>?
    private let readsHands = CommandLine.arguments.contains("--hands")
    private lazy var handCalibration: (HandCalibration, String) = {
        if let defaults = UserDefaults(suiteName: "io.github.phanipaladugula.glazer"),
            let saved = Preferences(store: defaults).handCalibration
        {
            return (saved, "your calibration")
        }
        return (.typical, "a typical hand")
    }()

    func run() async {
        switch await CameraAccess.request() {
        case .granted:
            break
        case .denied, .restricted:
            print(
                "Camera access is off for this terminal app. Allow it in System Settings › Privacy & Security › Camera."
            )
            exit(1)
        case .notDetermined:
            print("Camera access wasn't granted.")
            exit(1)
        }

        if readsHands {
            camera.setWantsHands(true)
            print("Open and close your hand, read against \(handCalibration.1). Ctrl-C to stop.\n")
        } else {
            print("Turn your head between your displays. Ctrl-C to stop.\n")
        }
        do {
            try await camera.start { [weak self] frame in
                Task { @MainActor in self?.handle(frame) }
            }
        } catch {
            print("The camera couldn't start: \(error)")
            exit(1)
        }
    }

    private func handle(_ frame: Frame) {
        let light = lightMeter.update(brightness: frame.brightness)
        var line = "faces \(frame.faces.count)"

        if case .user(let face) = tracker.update(with: frame) {
            let pose = filter.filter(face.pose, at: frame.timestamp)
            yawRange =
                yawRange.map { min($0.lowerBound, pose.yaw)...max($0.upperBound, pose.yaw) } ?? pose.yaw...pose.yaw
            line += String(format: "  ·  yaw %+6.1f°  pitch %+6.1f°", pose.yaw, pose.pitch)
            if let yawRange {
                line += String(format: "  ·  range %+.0f° to %+.0f°", yawRange.lowerBound, yawRange.upperBound)
            }
        } else {
            filter.reset()
            line += "  ·  no face followed"
        }
        line += "  ·  light \(light)" + String(format: " (%.0f%%)", frame.brightness * 100)
        if readsHands {
            if let hand = frame.hand {
                let features = hand.features
                line += String(
                    format: "  ·  hand %3.0f%% open  (reach %.2f, curl %.2f, spread %.2f, size %.2f)",
                    handCalibration.0.openness(of: features) * 100, features.reach, features.curl, features.spread,
                    hand.size)
            } else {
                line += "  ·  no hand"
            }
        }

        guard frame.timestamp - lastPrint >= 0.2 else { return }
        lastPrint = frame.timestamp
        print("\r\u{1B}[2K" + line, terminator: "")
        fflush(stdout)
    }
}

signal(SIGINT) { _ in
    print("\n")
    exit(0)
}

let check = MainActor.assumeIsolated { CameraCheck() }
Task { @MainActor in await check.run() }
RunLoop.main.run()
