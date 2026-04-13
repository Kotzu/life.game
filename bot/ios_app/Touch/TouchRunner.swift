/// Touch injection via XCTest – necesita Developer Mode.
/// Adauga acest fisier in targetul "BotBridgeTouch" (UI Testing Bundle).
/// Targetul ruleaza un server HTTP local care primeste comenzi de la BotLoop.
///
/// Activare Developer Mode (iPhone 16 Pro Max):
///   1. Conecteaza la Mac cu Xcode cel putin o data
///   2. Settings → Privacy & Security → Developer Mode → ON
///   3. Rebuild si reinstaleaza app-ul

import XCTest
import Foundation

// MARK: – HTTP Server pentru comenzi de touch

class TouchServer {
    private var server: TouchHTTPServer?

    func start(port: UInt16 = 27753) {
        server = TouchHTTPServer(port: port)
        server?.start()
        print("TouchServer pornit pe portul \(port)")
    }
}

// MARK: – Touch Injector via XCUIDevice

class TouchInjector {
    private let app = XCUIApplication()

    func tap(x: CGFloat, y: CGFloat) {
        let screenSize = XCUIScreen.main.screenshot().image.size
        let normalized = XCUICoordinate(
            referencedElement: app,
            normalizedOffset: CGVector(
                dx: x / screenSize.width,
                dy: y / screenSize.height
            )
        )
        normalized.tap()
    }

    func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat) {
        let screenSize = XCUIScreen.main.screenshot().image.size
        let from = XCUICoordinate(
            referencedElement: app,
            normalizedOffset: CGVector(dx: fromX / screenSize.width, dy: fromY / screenSize.height)
        )
        let to = XCUICoordinate(
            referencedElement: app,
            normalizedOffset: CGVector(dx: toX / screenSize.width, dy: toY / screenSize.height)
        )
        from.press(forDuration: 0.1, thenDragTo: to)
    }

    func screenshot() -> Data? {
        XCUIScreen.main.screenshot().pngRepresentation
    }
}

// MARK: – Test Runner (entry point XCTest bundle)

class BotTouchTests: XCTestCase {
    static let injector = TouchInjector()
    static let server   = TouchServer()

    override class func setUp() {
        // Porneste serverul HTTP inainte de orice test
        server.start(port: 27753)
    }

    /// Test "infinit" – tine bundle-ul activ pentru a procesa comenzi
    func testRunTouchServer() throws {
        // Seteaza app-ul tinta (Dota Underlords bundle ID)
        let app = XCUIApplication(bundleIdentifier: "com.valvesoftware.underlords")
        app.activate()

        // Asteapta comenzi de la BotLoop (via HTTP)
        // Server-ul ruleaza in fundal, acest test nu se termina pana nu e oprit manual
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 3600)) // 1 ora
    }
}

// MARK: – Minimal HTTP server (fara dependinte externe)

class TouchHTTPServer {
    private let port: UInt16
    private var thread: Thread?

    init(port: UInt16) { self.port = port }

    func start() {
        thread = Thread { [weak self] in self?.run() }
        thread?.start()
    }

    private func run() {
        // Foloseste CFSocket pentru server TCP simplu
        var context = CFSocketContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                      retain: nil, release: nil, copyDescription: nil)
        guard let socket = CFSocketCreate(nil, AF_INET, SOCK_STREAM, IPPROTO_TCP,
                                          CFSocketCallBackType.acceptCallBack.rawValue,
                                          touchAcceptCallback, &context) else { return }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let data = withUnsafeBytes(of: &addr) { Data($0) } as CFData
        CFSocketSetAddress(socket, data)

        let source = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        CFRunLoopRun()
    }
}

// C callback pentru accept
private func touchAcceptCallback(_ socket: CFSocket?, _ callbackType: CFSocketCallBackType,
                                  _ address: CFData?, _ data: UnsafeRawPointer?, _ info: UnsafeMutableRawPointer?) {
    guard let data, callbackType == .acceptCallBack else { return }
    let fd = data.load(as: CFSocketNativeHandle.self)
    handleConnection(fd: fd)
}

private func handleConnection(fd: Int32) {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = recv(fd, &buffer, buffer.count, 0)
    guard bytesRead > 0 else { close(fd); return }

    let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

    // Parse JSON body din POST request
    if let bodyStart = request.range(of: "\r\n\r\n") {
        let body = String(request[bodyStart.upperBound...])
        if let jsonData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

            let x = CGFloat((json["x"] as? Double) ?? 0)
            let y = CGFloat((json["y"] as? Double) ?? 0)
            let action = json["action"] as? String ?? "tap"

            let injector = BotTouchTests.injector
            switch action {
            case "tap":
                injector.tap(x: x, y: y)
            case "swipe":
                let tx = CGFloat((json["to_x"] as? Double) ?? 0)
                let ty = CGFloat((json["to_y"] as? Double) ?? 0)
                injector.swipe(fromX: x, fromY: y, toX: tx, toY: ty)
            default: break
            }
        }
    }

    let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
    response.withCString { send(fd, $0, strlen($0), 0) }
    close(fd)
}
