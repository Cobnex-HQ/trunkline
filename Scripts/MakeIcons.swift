import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// The SVG is the only production artwork input. The approved raster is retained
// as a design reference. Pin the renderer so SVG filter support is reproducible.
let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || (arguments.count == 2 && arguments[0] == "--output-root") else {
    fail("Usage: swift Scripts/MakeIcons.swift [--output-root DIRECTORY]")
}
let root = arguments.isEmpty ? sourceRoot : URL(fileURLWithPath: arguments[1])
let renderer = ProcessInfo.processInfo.environment["TRUNKLINE_RESVG"].map { URL(fileURLWithPath: $0) }
    ?? sourceRoot.appendingPathComponent(".build/brand-tools/bin/resvg")
guard FileManager.default.isExecutableFile(atPath: renderer.path) else {
    fail("Install the artwork renderer: cargo install resvg --version 0.49.0 --locked --root .build/brand-tools")
}
let version = Process(); version.executableURL = renderer; version.arguments = ["--version"]
let versionOutput = Pipe(); version.standardOutput = versionOutput
try version.run()
let rendererVersion = String(decoding: versionOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
version.waitUntilExit()
guard version.terminationStatus == 0, rendererVersion.trimmingCharacters(in: .whitespacesAndNewlines) == "0.49.0" else {
    fail("Artwork export requires resvg 0.49.0, found: \(rendererVersion)")
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("TrunklineIcons-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let artwork = try XMLDocument(contentsOf: sourceRoot.appendingPathComponent("Assets/Branding/trunkline-icon.svg"))
guard let artworkRoot = artwork.rootElement(),
      let elephant = try artwork.nodes(forXPath: "//*[@id='elephant']").first as? XMLElement,
      let definitions = artworkRoot.elements(forName: "defs").first else {
    fatalError("Vector artwork must contain definitions and the elephant group")
}
// The inline mark uses precisely the same geometry, without tile or shadows.
let markRoot = XMLElement(name: "svg")
for (name, value) in ["xmlns":"http://www.w3.org/2000/svg", "width":"1024", "height":"1024", "viewBox":"160 152 920 920", "role":"img", "aria-labelledby":"title desc"].sorted(by: { $0.key < $1.key }) {
    markRoot.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
}
for name in ["title", "desc"] {
    if let element = artworkRoot.elements(forName: name).first { markRoot.addChild(element.copy() as! XMLElement) }
}
markRoot.addChild(definitions.copy() as! XMLElement)
markRoot.addChild(elephant.copy() as! XMLElement)
for element in try markRoot.nodes(forXPath: ".//*[@filter]") {
    (element as? XMLElement)?.removeAttribute(forName: "filter")
}
for element in try markRoot.nodes(forXPath: ".//*[local-name()='filter']") { element.detach() }
let markData = XMLDocument(rootElement: markRoot).xmlData(options: .nodePrettyPrint)

func render(_ document: XMLDocument, name: String) throws -> CGImage {
    let svg = temporary.appendingPathComponent(name + ".svg")
    let png = temporary.appendingPathComponent(name + ".png")
    try document.xmlData().write(to: svg)
    let process = Process(); process.executableURL = renderer
    process.arguments = ["--width", "2048", svg.path, png.path]
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0,
          let source = CGImageSourceCreateWithURL(png as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Could not render vector artwork")
    }
    return image
}
let macArtwork = try render(artwork, name: "mac")
// iOS supplies its own corner mask; use an opaque square tile, without a baked rim.
artworkRoot.attribute(forName: "viewBox")?.stringValue = "89 103 1072 1072"
for element in try artwork.nodes(forXPath: "//*[@id='app-tile']/*") {
    guard let rect = element as? XMLElement else { continue }
    if rect.attribute(forName: "fill")?.stringValue == "none" { rect.detach() }
    else { rect.attribute(forName: "rx")?.stringValue = "0" }
}
let mobileArtwork = try render(artwork, name: "mobile")
try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets/Branding"), withIntermediateDirectories: true)
try markData.write(to: root.appendingPathComponent("Assets/Branding/trunkline-elephant.svg"))

func draw(size: Int, path: String) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let macIcon = path.contains("Apps/macOS") && path.contains("AppIcon.appiconset")
    let alpha: CGImageAlphaInfo = macIcon ? .premultipliedLast : .noneSkipLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: alpha.rawValue)!
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.interpolationQuality = .high
    if macIcon {
        context.draw(macArtwork, in: bounds)
    } else {
        context.setFillColor(CGColor(red: 0, green: 0.075, blue: 0.278, alpha: 1))
        context.fill(bounds)
        context.draw(mobileArtwork, in: bounds)
    }
    let image = context.makeImage()!
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
}
try draw(size: 1024, path: root.appendingPathComponent("Assets/Branding/elephant-logo.png").path)
for platform in ["Apps/iOS/Resources", "Apps/macOS/Resources"] {
    let catalog = root.appendingPathComponent(platform + "/Assets.xcassets")
    let logo = catalog.appendingPathComponent("ElephantLogo.imageset")
    try FileManager.default.createDirectory(at: logo, withIntermediateDirectories: true)
    try draw(size: 512, path: logo.appendingPathComponent("elephant.png").path)
    try JSONSerialization.data(withJSONObject: ["info":["author":"xcode","version":1], "images":[["filename":"elephant.png","idiom":"universal"]]], options: [.prettyPrinted, .sortedKeys]).write(to: logo.appendingPathComponent("Contents.json"))
    let mark = catalog.appendingPathComponent("ElephantMark.imageset")
    try FileManager.default.createDirectory(at: mark, withIntermediateDirectories: true)
    try Data(contentsOf: root.appendingPathComponent("Assets/Branding/trunkline-elephant.svg")).write(to: mark.appendingPathComponent("elephant.svg"))
    try JSONSerialization.data(withJSONObject: ["info":["author":"xcode","version":1],
        "images":[["filename":"elephant.svg","idiom":"universal"]],
        "properties":["preserves-vector-representation":true]], options: [.prettyPrinted, .sortedKeys]).write(to: mark.appendingPathComponent("Contents.json"))
    let accent = catalog.appendingPathComponent("AccentColor.colorset")
    try FileManager.default.createDirectory(at: accent, withIntermediateDirectories: true)
    let day: [String: Any] = ["idiom":"universal","color":["color-space":"srgb","components":["red":"0.118","green":"0.318","blue":"0.584","alpha":"1.000"]]]
    let night: [String: Any] = ["idiom":"universal","appearances":[["appearance":"luminosity","value":"dark"]],
        "color":["color-space":"srgb","components":["red":"0.655","green":"0.824","blue":"0.937","alpha":"1.000"]]]
    try JSONSerialization.data(withJSONObject: ["info":["author":"xcode","version":1],"colors":[day, night]], options: [.prettyPrinted, .sortedKeys]).write(to: accent.appendingPathComponent("Contents.json"))
    let control = catalog.appendingPathComponent("ControlSurface.colorset")
    try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
    let controlDay: [String: Any] = ["idiom":"universal","color":["color-space":"srgb","components":["red":"0.071","green":"0.208","blue":"0.396","alpha":"1.000"]]]
    let controlNight: [String: Any] = ["idiom":"universal","appearances":[["appearance":"luminosity","value":"dark"]],
        "color":["color-space":"srgb","components":["red":"0.082","green":"0.227","blue":"0.376","alpha":"1.000"]]]
    try JSONSerialization.data(withJSONObject: ["info":["author":"xcode","version":1],"colors":[controlDay, controlNight]], options: [.prettyPrinted, .sortedKeys]).write(to: control.appendingPathComponent("Contents.json"))
    let directory = catalog.appendingPathComponent("AppIcon.appiconset")
    var images: [[String: String]] = []
    if platform == "Apps/iOS/Resources" {
        for idiom in ["iphone", "ipad"] {
            for points in (idiom == "iphone" ? [20.0,29,40,60] : [20.0,29,40,76,83.5]) {
                for scale in (idiom == "iphone" ? [2,3] : (points == 83.5 ? [2] : [1,2])) {
                    let file = "icon-\(idiom)-\(points)-\(scale).png"
                    try draw(size: Int(points * Double(scale)), path: directory.appendingPathComponent(file).path)
                    images.append(["filename":file,"idiom":idiom,"size":"\(points)x\(points)","scale":"\(scale)x"])
                }
            }
        }
        try draw(size: 1024, path: directory.appendingPathComponent("AppStore.png").path)
        images.append(["filename":"AppStore.png","idiom":"ios-marketing","size":"1024x1024","scale":"1x"])
    } else {
        for points in [16,32,128,256,512] {
            for scale in [1,2] {
                let file = "icon-\(points)-\(scale).png"
                try draw(size: points * scale, path: directory.appendingPathComponent(file).path)
                images.append(["filename":file,"idiom":"mac","size":"\(points)x\(points)","scale":"\(scale)x"])
            }
        }
    }
    let info: [String: Any] = ["info":["author":"xcode","version":1],"images":images]
    try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
    try JSONSerialization.data(withJSONObject: ["info":["author":"xcode","version":1]], options: [.prettyPrinted, .sortedKeys]).write(to: catalog.appendingPathComponent("Contents.json"))
}
print("Generated iPhone, iPad, App Store, and Mac app icons")
