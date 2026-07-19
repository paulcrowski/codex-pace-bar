import Darwin
import Foundation

private func argument(named name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else { return nil }
    return CommandLine.arguments[index + 1]
}

guard let eventPath = argument(named: "--event-file"),
      let input = try? FileHandle.standardInput.readToEnd(),
      !input.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
else {
    exit(0)
}

let allowedKeys = [
    "session_id", "turn_id", "cwd", "hook_event_name", "model", "transcript_path"
]
var sanitized: [String: Any] = [:]
for key in allowedKeys {
    if let value = object[key], !(value is NSNull) {
        sanitized[key] = value
    }
}
if sanitized["cwd"] == nil {
    let workingDirectory = FileManager.default.currentDirectoryPath
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !workingDirectory.isEmpty {
        sanitized["cwd"] = workingDirectory
    }
}
guard sanitized["session_id"] != nil,
      sanitized["turn_id"] != nil,
      sanitized["hook_event_name"] != nil
else {
    exit(0)
}

let environment = ProcessInfo.processInfo.environment
sanitized["generated_at"] = Date().timeIntervalSince1970
sanitized["terminal_program"] = environment["TERM_PROGRAM"]
sanitized["terminal_session_id"] = environment["ITERM_SESSION_ID"] ?? environment["TERM_SESSION_ID"]
sanitized["source_bundle_identifier"] = environment["__CFBundleIdentifier"]

guard var output = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]) else {
    exit(0)
}
output.append(0x0A)

let eventURL = URL(fileURLWithPath: eventPath)
try? FileManager.default.createDirectory(
    at: eventURL.deletingLastPathComponent(),
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700]
)
let descriptor = open(eventPath, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
guard descriptor >= 0 else { exit(0) }
defer { close(descriptor) }
flock(descriptor, LOCK_EX)
defer { flock(descriptor, LOCK_UN) }
var fileStatus = stat()
if fstat(descriptor, &fileStatus) == 0, fileStatus.st_size > 4 * 1_024 * 1_024 {
    _ = ftruncate(descriptor, 0)
}
_ = output.withUnsafeBytes { bytes in
    write(descriptor, bytes.baseAddress, bytes.count)
}
