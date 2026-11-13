import CoreAudio
import Foundation
import os

/// 输入设备实时电平：IOProc 回调里算峰值，主线程按需读取。
/// 权限未授予或设备不支持 IOProc 时保持空转（读到的始终是 0），不造数据。
final class InputLevelMeter: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let callbackQueue = DispatchQueue(label: "com.littlewatch.inputlevel", qos: .userInteractive)

    private struct State {
        var deviceID: AudioObjectID?
        var procID: AudioDeviceIOProcID?
        var peak: Float = 0
    }

    enum StartError: Error {
        case noDevice
    }

    /// 幂等：同一设备已在跑则直接返回；换了设备就先停旧的再起新的。
    func start(deviceID target: AudioObjectID) throws {
        try state.withLock { state in
            if state.procID != nil, state.deviceID == target { return }

            if let oldDevice = state.deviceID, let oldProcID = state.procID {
                AudioDeviceStop(oldDevice, oldProcID)
                AudioDeviceDestroyIOProcID(oldDevice, oldProcID)
                state.deviceID = nil
                state.procID = nil
                state.peak = 0
            }

            var procID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&procID, target, callbackQueue) { _, inputData, _, _, _ in
                let peak = Self.peak(of: inputData)
                // 实时线程只做一次原子写，不做锁内计算以外的开销。
                self.state.withLock { $0.peak = peak }
            }
            guard status == noErr, let created = procID else {
                throw StartError.noDevice
            }
            state.procID = created
            state.deviceID = target
            AudioDeviceStart(target, created)
        }
    }

    func stop() {
        state.withLock { state in
            guard let deviceID = state.deviceID, let procID = state.procID else { return }
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            state.deviceID = nil
            state.procID = nil
            state.peak = 0
        }
    }

    /// 0...1 的最新峰值，读取后不清零（由下一次回调自然覆盖）。
    func currentPeak() -> Double {
        state.withLock { Double($0.peak) }
    }

    private static func peak(of bufferList: UnsafePointer<AudioBufferList>) -> Float {
        var peak: Float = 0
        let mutable = UnsafeMutablePointer(mutating: bufferList)
        for buffer in UnsafeMutableAudioBufferListPointer(mutable) {
            guard let data = buffer.mData else { continue }
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            guard sampleCount > 0 else { continue }
            let samples = data.bindMemory(to: Float32.self, capacity: sampleCount)
            var index = 0
            while index < sampleCount {
                let sample = abs(samples[index])
                if sample > peak { peak = sample }
                index += 1
            }
        }
        return min(peak, 1)
    }
}
