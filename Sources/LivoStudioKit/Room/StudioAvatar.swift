import SwiftUI

enum StudioAvatar {
    static let palette: [Color] = [
        Color(red: 0.25, green: 0.45, blue: 0.72),
        Color(red: 0.55, green: 0.32, blue: 0.58),
        Color(red: 0.20, green: 0.55, blue: 0.48),
        Color(red: 0.72, green: 0.42, blue: 0.22),
        Color(red: 0.30, green: 0.38, blue: 0.62),
        Color(red: 0.62, green: 0.28, blue: 0.38),
    ]

    static func initials(_ name: String) -> String {
        StudioChatGrouping.initials(name)
    }

    static func color(for name: String) -> Color {
        var hash = 0
        for scalar in name.unicodeScalars {
            hash = hash &* 31 &+ Int(scalar.value)
        }
        return palette[Int(hash.magnitude % UInt(palette.count))]
    }
}

struct StudioAvatarView: View {
    var name: String
    var picture: String?
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(StudioAvatar.color(for: name))
            if let url = picture.flatMap(URL.init(string:)), !url.absoluteString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        initialsLabel
                    }
                }
                .clipShape(Circle())
            } else {
                initialsLabel
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var initialsLabel: some View {
        Text(StudioAvatar.initials(name))
            .font(.system(size: max(11, diameter * 0.36), weight: .semibold))
            .foregroundStyle(.white)
    }
}
