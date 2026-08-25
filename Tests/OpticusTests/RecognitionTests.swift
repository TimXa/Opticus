import XCTest
@testable import Opticus

final class RecognitionTests: XCTestCase {
    func testPersonalClassifierSeparatesCalibratedStates() throws {
        let bare = (0..<CalibrationPose.samplesPerClass).map { index in
            VisionVector([0.10, 0.11, 0.08, 0.04, 0.05, 0.93].map { $0 + Double(index % 3) * 0.001 })
        }
        let glasses = (0..<CalibrationPose.samplesPerClass).map { index in
            VisionVector([0.28, 0.30, 0.22, 0.15, 0.14, 0.88].map { $0 + Double(index % 3) * 0.001 })
        }
        let profile = CalibrationProfile(withGlasses: glasses, withoutGlasses: bare)

        let on = try XCTUnwrap(profile.prediction(for: VisionVector([0.29, 0.30, 0.23, 0.15, 0.15, 0.88])))
        let off = try XCTUnwrap(profile.prediction(for: VisionVector([0.10, 0.11, 0.08, 0.04, 0.05, 0.93])))

        XCTAssertGreaterThan(on.glassesProbability, 0.9)
        XCTAssertLessThan(off.glassesProbability, 0.1)
    }

    func testTemporalFilterRequiresStableEvidence() {
        var filter = TemporalDecisionFilter()

        XCTAssertEqual(filter.update(probability: 0.99, now: 0), .unknown)
        XCTAssertEqual(filter.update(probability: 0.99, now: 0.1), .unknown)
        XCTAssertEqual(filter.candidateState, .withGlasses)
        XCTAssertEqual(filter.candidateProgress, 0, accuracy: 0.001)
        XCTAssertEqual(filter.update(probability: 0.99, now: 0.4), .unknown)
        XCTAssertGreaterThan(filter.candidateProgress, 0.5)
        XCTAssertEqual(filter.update(probability: 0.99, now: 0.6), .unknown)
        XCTAssertEqual(filter.update(probability: 0.99, now: 0.7), .withGlasses)
        XCTAssertEqual(filter.candidateProgress, 0)

        // A single contradictory frame must not flip the display mode.
        XCTAssertEqual(filter.update(probability: 0.01, now: 0.8), .withGlasses)
    }

    func testRecognitionWorksBeforePersonalCalibration() {
        XCTAssertEqual(RecognitionSignal.fused(neural: 0.91, personal: nil), 0.91)
        XCTAssertEqual(
            RecognitionSignal.fused(neural: 0.8, personal: 0.4)!,
            0.76,
            accuracy: 0.0001
        )
    }

    func testPoseBucketsCoverEnrollmentTurn() {
        XCTAssertEqual(PoseBucket.from(yaw: -0.2), .left)
        XCTAssertEqual(PoseBucket.from(yaw: 0), .center)
        XCTAssertEqual(PoseBucket.from(yaw: 0.2), .right)
    }

    func testEightPoseEnrollmentUsesMeasuredHeadGeometry() {
        XCTAssertTrue(CalibrationPose.front.matches(yaw: 0, roll: 0, faceWidth: 0.3, baselineWidth: nil))
        XCTAssertTrue(CalibrationPose.turnLeft.matches(yaw: -0.2, roll: 0, faceWidth: 0.3, baselineWidth: 0.3))
        XCTAssertTrue(CalibrationPose.turnRight.matches(yaw: 0.2, roll: 0, faceWidth: 0.3, baselineWidth: 0.3))
        XCTAssertTrue(CalibrationPose.tiltLeft.matches(yaw: 0, roll: 0.2, faceWidth: 0.3, baselineWidth: 0.3))
        XCTAssertTrue(CalibrationPose.lookDown.matches(
            yaw: 0, roll: 0, pitchSignal: 0.48, baselinePitchSignal: 0.44,
            faceWidth: 0.3, baselineWidth: 0.3
        ))
        XCTAssertTrue(CalibrationPose.closer.matches(yaw: 0, roll: 0, faceWidth: 0.36, baselineWidth: 0.3))
        XCTAssertTrue(CalibrationPose.farther.matches(yaw: 0, roll: 0, faceWidth: 0.24, baselineWidth: 0.3))
    }
}
