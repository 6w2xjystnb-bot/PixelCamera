import Foundation
import CoreMotion
import Accelerate

actor MotionMeter {
    static let shared = MotionMeter()
    
    private let motionManager = CMMotionManager()
    private var motionReadings: [CMDeviceMotion] = []
    
    struct MotionMetrics {
        let angularVelocityMagnitude: Double
        let accelerationMagnitude: Double
        let isStable: Bool
        let recommendedFrames: Int
        let maxExposureSeconds: Double
    }
    
    func measureMotion(duration: TimeInterval = 0.5) async -> MotionMetrics {
        guard motionManager.isDeviceMotionAvailable else {
            return MotionMetrics(angularVelocityMagnitude: 0, accelerationMagnitude: 0, isStable: false, recommendedFrames: 6, maxExposureSeconds: 0.25)
        }
        
        motionReadings.removeAll()
        motionManager.deviceMotionUpdateInterval = 0.01
        
        let semaphore = DispatchSemaphore(value: 0)
        
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            if let motion = motion {
                self?.motionReadings.append(motion)
            }
        }
        
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        motionManager.stopDeviceMotionUpdates()
        
        return analyzeMotion()
    }
    
    func analyzeMotionData(_ motions: [CMDeviceMotion]) -> MotionMetrics {
        motionReadings = motions
        return analyzeMotion()
    }
    
    private func analyzeMotion() -> MotionMetrics {
        guard !motionReadings.isEmpty else {
            return MotionMetrics(angularVelocityMagnitude: 0, accelerationMagnitude: 0, isStable: false, recommendedFrames: 6, maxExposureSeconds: 0.25)
        }
        
        var gyroMagnitudes: [Double] = []
        var accelMagnitudes: [Double] = []
        
        for motion in motionReadings {
            let gyro = motion.rotationRate
            let gyroMag = sqrt(gyro.x * gyro.x + gyro.y * gyro.y + gyro.z * gyro.z)
            gyroMagnitudes.append(gyroMag)
            
            let accel = motion.userAcceleration
            let accelMag = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            accelMagnitudes.append(accelMag)
        }
        
        let avgGyro = gyroMagnitudes.reduce(0, +) / Double(gyroMagnitudes.count)
        let avgAccel = accelMagnitudes.reduce(0, +) / Double(accelMagnitudes.count)
        
        // Determine stability
        let isStable = avgGyro < 0.5 && avgAccel < 0.1
        
        // Adaptive frame count: more motion = more frames needed for denoising
        let recommendedFrames: Int
        let maxExposure: Double
        
        if isStable {
            recommendedFrames = 15
            maxExposure = 1.0 / 3.0
        } else if avgGyro < 2.0 {
            recommendedFrames = 12
            maxExposure = 1.0 / 6.0
        } else if avgGyro < 5.0 {
            recommendedFrames = 9
            maxExposure = 1.0 / 10.0
        } else {
            recommendedFrames = 6
            maxExposure = 1.0 / 15.0
        }
        
        return MotionMetrics(
            angularVelocityMagnitude: avgGyro,
            accelerationMagnitude: avgAccel,
            isStable: isStable,
            recommendedFrames: recommendedFrames,
            maxExposureSeconds: maxExposure
        )
    }
}
