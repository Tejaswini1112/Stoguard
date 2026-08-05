import SwiftUI

struct AppMark: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.14, blue: 0.28), Theme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "internaldrive.fill")
                .font(.system(size: size * 0.46, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
    }
}
