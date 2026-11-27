// Local speech-to-text server for Laf: Parakeet TDT on the Neural Engine (FluidAudio / Core ML).
// Speaks the same API as whisper.cpp's whisper-server: POST /inference (multipart "file" = WAV) -> {"text": "..."}.
// usage: parakeet-server [--host 127.0.0.1] [--port 8178] [--model v2|v3|ultra|phonon2]
import FluidAudio
import Foundation
import Network

func log(_ s: String) { FileHandle.standardError.write(Data("[parakeet] \(s)\n".utf8)) }

var host = "127.0.0.1", port: UInt16 = 8178, modelName = "v2"
var argv = CommandLine.arguments.dropFirst().makeIterator()
while let a = argv.next() {
    switch a {
    case "--host": host = argv.next() ?? host
    case "--port": port = UInt16(argv.next() ?? "") ?? port
    case "--model": modelName = argv.next() ?? modelName
    default: log("ignoring argument \(a)")
    }
}
let versions: [String: AsrModelVersion] = ["v2": .v2, "v3": .v3, "ultra": .ultra, "phonon2": .phonon2]
guard let version = versions[modelName] else { log("unknown model \(modelName)"); exit(2) }

/// Loads the model once and transcribes one request at a time.
actor Transcriber {
    private let asr = AsrManager(config: .default)
    private let version: AsrModelVersion
    private var loading: Task<Void, Error>?

    init(version: AsrModelVersion) { self.version = version }

    func load() async throws {
        if loading == nil {
            let asr = asr, version = version
            loading = Task {
                let started = Date()
                try await asr.loadModels(try await AsrModels.downloadAndLoad(version: version))
                log("model \(version) ready in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            }
        }
        try await loading!.value
    }

    func transcribe(wav: Data) async throws -> String {
        try await load()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("parakeet-\(UUID().uuidString).wav")
        try wav.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var samples = try AudioConverter().resampleAudioFile(file)
        // Parakeet rejects clips under a second; pad short ones with silence.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: 16000)
        if samples.count < minimum { samples += [Float](repeating: 0, count: minimum - samples.count) }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(samples, decoderState: &state).text
    }
}

let transcriber = Transcriber(version: version)

/// The bytes of the multipart part named "file".
func filePart(_ body: Data, contentType: String) -> Data? {
    guard let b = contentType.range(of: "boundary=") else { return nil }
    let boundary = Data(("--" + contentType[b.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))).utf8)
    var cursor = body.startIndex
    while let start = body.range(of: boundary, in: cursor..<body.endIndex) {
        guard let headerEnd = body.range(of: Data("\r\n\r\n".utf8), in: start.upperBound..<body.endIndex) else { return nil }
        let headers = String(decoding: body[start.upperBound..<headerEnd.lowerBound], as: UTF8.self)
        let end = body.range(of: Data("\r\n".utf8) + boundary, in: headerEnd.upperBound..<body.endIndex)?.lowerBound ?? body.endIndex
        if headers.contains("name=\"file\"") { return body[headerEnd.upperBound..<end] }
        cursor = end
    }
    return nil
}

func respond(_ conn: NWConnection, _ status: String, _ json: [String: Any]) {
    let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
}

func handle(_ conn: NWConnection, buffer: Data = Data()) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { chunk, _, done, error in
        var data = buffer
        if let chunk { data.append(chunk) }
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            if done || error != nil { conn.cancel() } else { handle(conn, buffer: data) }
            return
        }
        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            if let c = line.firstIndex(of: ":") {
                headers[line[..<c].lowercased()] = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let length = Int(headers["content-length"] ?? "") ?? 0
        let body = data[headerEnd.upperBound...]
        if body.count < length && !done && error == nil { handle(conn, buffer: data); return }

        let request = head.first?.split(separator: " ") ?? []
        guard request.count >= 2, request[0] == "POST", request[1].hasPrefix("/inference") else {
            respond(conn, request.first == "GET" ? "200 OK" : "404 Not Found", ["status": "ok", "model": modelName])
            return
        }
        guard let wav = filePart(Data(body), contentType: headers["content-type"] ?? "") else {
            respond(conn, "400 Bad Request", ["error": "missing multipart field \"file\""])
            return
        }
        Task {
            do {
                let started = Date()
                let text = try await transcriber.transcribe(wav: wav)
                log(String(format: "%.0f ms for %d KB", Date().timeIntervalSince(started) * 1000, wav.count / 1024))
                respond(conn, "200 OK", ["text": text])
            } catch {
                log("transcription failed: \(error)")
                respond(conn, "500 Internal Server Error", ["error": "\(error)"])
            }
        }
    }
}

let params = NWParameters.tcp
params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
params.allowLocalEndpointReuse = true
let listener = try NWListener(using: params)
listener.newConnectionHandler = { conn in
    conn.start(queue: .global())
    handle(conn)
}
listener.stateUpdateHandler = { state in
    switch state {
    case .ready: log("listening on \(host):\(port)")
    case .failed(let error): log("listener failed: \(error)"); exit(1)
    default: break
    }
}
listener.start(queue: .main)
Task { do { try await transcriber.load() } catch { log("model load failed: \(error)"); exit(1) } }
dispatchMain()
