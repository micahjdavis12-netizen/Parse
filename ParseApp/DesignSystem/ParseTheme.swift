import SwiftUI

enum ParseTheme {
    static let minWindowWidth: CGFloat = 700
    static let minWindowHeight: CGFloat = 400
    static let defaultWindowWidth: CGFloat = 880
    static let defaultWindowHeight: CGFloat = 520
    static let cornerRadius: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let explanationFont: Font = .system(size: 13, weight: .regular)
    static let captionFont: Font = .system(size: 11, weight: .medium)
    static let monoFont: Font = .system(size: 12, design: .monospaced)
    static let headerFont: Font = .system(size: 12, weight: .semibold)

    static let insertGreen = Color.green.opacity(0.16)
    static let deleteRed = Color.red.opacity(0.16)

    static let islandSize = CGSize(width: 248, height: 44)
    static let islandCornerRadius: CGFloat = 14
    static let islandScreenOffset: CGFloat = 96
    static let islandWindowPadding: CGFloat = 12
    static let islandWindowSize = CGSize(
        width: islandSize.width + islandWindowPadding * 2,
        height: islandSize.height + islandWindowPadding * 2
    )
}
