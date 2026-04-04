import Cocoa
import FxPlug

/// Custom NSView displayed in FCP/Motion's inspector for the LUT file parameter.
/// Uses direct drawing (no subviews) for maximum compatibility with the XPC view service bridge.
class LUTCustomView: NSView {
    private let defaultLabel = "Choose LUT…"
    private var currentLabel = "Choose LUT…"

    weak var apiManager: (any PROAPIAccessing)?
    var parameterID: UInt32 = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func updateLabel(_ text: String) {
        currentLabel = text.isEmpty ? defaultLabel : text
        needsDisplay = true
    }

    func refreshLabel() {
        guard let apiManager else {
            updateLabel(defaultLabel)
            return
        }
        guard let actionAPI = apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4 else {
            updateLabel(defaultLabel)
            return
        }
        guard let retrievalAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6 else {
            updateLabel(defaultLabel)
            return
        }

        actionAPI.startAction(self)
        defer { actionAPI.endAction(self) }

        var customValue: (any NSObjectProtocol & NSSecureCoding & NSCopying)?
        retrievalAPI.getCustomParameterValue(&customValue, fromParameter: parameterID, at: actionAPI.currentTime())
        let lutName = (customValue as? LUTFileData)?.name ?? defaultLabel
        updateLabel(lutName == "None" ? defaultLabel : lutName)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lutLog("viewDidMoveToWindow: frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds)) window=\(String(describing: window))")
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                self?.refreshLabel()
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        lutLog("draw: frame=\(NSStringFromRect(frame)) bounds=\(NSStringFromRect(bounds)) dirtyRect=\(NSStringFromRect(dirtyRect))")

        guard bounds.width > 1, bounds.height > 1 else { return }

        // Draw the entire view as a clickable button
        let bezelRect = bounds.insetBy(dx: 2, dy: 2)
        let bezelPath = NSBezierPath(roundedRect: bezelRect, xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        bezelPath.fill()
        NSColor(calibratedWhite: 0.5, alpha: 1).setStroke()
        bezelPath.lineWidth = 1
        bezelPath.stroke()

        // Draw label text centered
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]
        let textRect = bezelRect.insetBy(dx: 8, dy: 4)
        (currentLabel as NSString).draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Click handling

    override func mouseDown(with event: NSEvent) {
        chooseLUT()
    }

    private func chooseLUT() {
        guard let apiManager = apiManager else { return }
        guard let windowAPI = apiManager.api(for: FxRemoteWindowAPI.self) as? FxRemoteWindowAPI else {
            lutLog("chooseLUT: remote window API unavailable")
            return
        }

        windowAPI.remoteWindow(of: CGSize(width: 1, height: 1)) { [weak self] parentView, error in
            guard let self else { return }
            guard error == nil else {
                lutLog("chooseLUT: failed to create remote window: \(error!.localizedDescription)")
                return
            }
            guard let parentView, let window = parentView.window else {
                lutLog("chooseLUT: remote window missing host window")
                return
            }

            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.allowedContentTypes = [.init(filenameExtension: "cube")!]
                panel.title = "Choose a LUT File"
                panel.message = "Select a .cube LUT file to embed in this effect"

                panel.beginSheetModal(for: window) { [weak self] response in
                    defer {
                        DispatchQueue.main.async {
                            window.orderOut(nil)
                            if let api3 = self?.apiManager?.api(for: FxRemoteWindowAPI_v3.self) as? FxRemoteWindowAPI_v3 {
                                api3.closeRemoteWindow()
                            }
                        }
                    }

                    guard let self else { return }
                    guard response == .OK, let url = panel.url else { return }
                    self.loadLUT(from: url)
                }
            }
        }
    }

    private func loadLUT(from url: URL) {
        do {
            let fileData = try Data(contentsOf: url)
            let name = url.deletingPathExtension().lastPathComponent

            _ = try CubeParser.parse(data: fileData)

            let lutFileData = LUTFileData(name: name, fileData: fileData)
            guard
                let apiManager,
                let actionAPI = apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4,
                let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5
            else {
                lutLog("loadLUT: parameter APIs unavailable while storing '\(name)'")
                return
            }

            let time = actionAPI.currentTime()
            actionAPI.startAction(self)
            settingAPI.setCustomParameterValue(lutFileData, toParameter: parameterID, at: time)
            actionAPI.endAction(self)

            updateLabel(name)
            lutLog("Stored LUT '\(name)' (\(fileData.count) bytes) in custom parameter")
        } catch {
            lutLog("loadLUT: failed to store LUT '\(url.lastPathComponent)': \(error.localizedDescription)")
            updateLabel("Error: \(error.localizedDescription)")
        }
    }
}
