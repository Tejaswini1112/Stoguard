import AppKit

/// macOS Finder-style sounds for trash actions.
enum SystemSound {
    private static let finderSounds =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/"

    static func playMoveToTrash() {
        if playFile("drag to trash.aif") { return }
        if playNamed("Trash") { return }
        playNamed("Pop")
    }

    static func playDeletePermanently() {
        if playFile("empty trash.aif") { return }
        if playFile("iTrash.aif") { return }
        playNamed("Funk")
    }

    static func playPutBack() {
        if playFile("put back.aif") { return }
        if playNamed("Tink") { return }
        playNamed("Pop")
    }

    @discardableResult
    private static func playNamed(_ name: String) -> Bool {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return false }
        sound.play()
        return true
    }

    @discardableResult
    private static func playFile(_ filename: String) -> Bool {
        let path = finderSounds + filename
        guard FileManager.default.fileExists(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true) else { return false }
        sound.play()
        return true
    }
}
