#if os(iOS)
import AVFoundation
import Observation

@MainActor
@Observable
final class VolumeButtonMonitor {
    var direction: Int?
    private var observation: NSKeyValueObservation?
    private var previousVolume: Float?

    func start() {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        previousVolume = session.outputVolume
        observation = session.observe(\AVAudioSession.outputVolume, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, let previousVolume = self.previousVolume else { return }
                self.previousVolume = newValue
                guard abs(newValue - previousVolume) > 0.001 else { return }
                self.direction = newValue > previousVolume ? 1 : -1
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        previousVolume = nil
        direction = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
