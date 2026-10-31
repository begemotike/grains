import Foundation

/// Crash-safe file replacement: readers see either the old file or the complete new one.
public enum AtomicFileWriter {
    /// Writes `data` to `<url>.tmp-<uuid>` in the same directory, `fsync`s it, then
    /// `rename(2)`s it over `url` and `fsync`s the directory. Creates the directory (and
    /// intermediates) if missing. On failure the temporary file is removed and the original
    /// file, if any, is untouched.
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temp = directory.appendingPathComponent("\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        let tempPath = temp.path
        let fd = open(tempPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw posixError() }

        var closed = false
        do {
            try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                var offset = 0
                while offset < buffer.count {
                    let n = Foundation.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                    if n < 0 {
                        if errno == EINTR { continue }
                        throw posixError()
                    }
                    offset += n
                }
            }
            // F_FULLFSYNC is the real durability barrier on macOS; fsync alone only reaches the drive cache.
            guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else { throw posixError() }
            closed = true
            guard close(fd) == 0 else { throw posixError() }
            guard rename(tempPath, url.path) == 0 else { throw posixError() }
        } catch {
            if !closed { close(fd) }
            unlink(tempPath)
            throw error
        }

        // Persist the directory entry; best effort (failure here does not undo the rename).
        let dirFD = open(directory.path, O_RDONLY | O_CLOEXEC)
        if dirFD >= 0 {
            _ = fsync(dirFD)
            close(dirFD)
        }
    }

    private static func posixError() -> Error {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
