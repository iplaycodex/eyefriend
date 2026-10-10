import AppKit

enum Artwork {
    static func image(_ name: String, extension fileExtension: String = "png") -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else { return NSImage(size: .zero) }
        return image
    }
}
