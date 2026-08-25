import Foundation

guard CommandLine.arguments.count >= 4 else {
    fputs("usage: make_icns output.icns type:path ...\n", stderr)
    exit(2)
}

func bigEndianData(_ value: UInt32) -> Data {
    var number = value.bigEndian
    return Data(bytes: &number, count: MemoryLayout<UInt32>.size)
}

var elements = Data()
for argument in CommandLine.arguments.dropFirst(2) {
    let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[0].utf8.count == 4 else {
        fputs("invalid icon element: \(argument)\n", stderr)
        exit(2)
    }
    let image = try Data(contentsOf: URL(fileURLWithPath: parts[1]))
    elements.append(parts[0].data(using: .ascii)!)
    elements.append(bigEndianData(UInt32(image.count + 8)))
    elements.append(image)
}

var output = Data("icns".utf8)
output.append(bigEndianData(UInt32(elements.count + 8)))
output.append(elements)
try output.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
