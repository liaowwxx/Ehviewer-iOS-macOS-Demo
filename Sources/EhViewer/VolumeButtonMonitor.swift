/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

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
