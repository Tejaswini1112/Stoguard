import SwiftUI

// MARK: - Shimmer skeleton primitives

struct SkeletonBlock: View {
    var height: CGFloat = 12
    var width: CGFloat? = nil
    var radius: CGFloat = 4

    @State private var phase = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.hairline.opacity(phase ? 0.45 : 0.22))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: phase)
            .onAppear { phase = true }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonBlock(height: 28, width: 28, radius: 6)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(height: 11, width: 120)
                SkeletonBlock(height: 9, width: 180)
            }
            Spacer(minLength: 0)
            SkeletonBlock(height: 11, width: 48)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct SkeletonGrid: View {
    let columns: Int
    let rows: Int

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns),
            spacing: 10
        ) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 14, width: 90)
                    SkeletonBlock(height: 10)
                    SkeletonBlock(height: 10, width: 100)
                    HStack {
                        SkeletonBlock(height: 24, width: 64, radius: 12)
                        Spacer()
                        SkeletonBlock(height: 24, width: 72, radius: 12)
                    }
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(12)
    }
}

struct SkeletonAppGrid: View {
    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130, maximum: 160), spacing: 10)],
            spacing: 10
        ) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(spacing: 8) {
                    SkeletonBlock(height: 40, width: 40, radius: 8)
                    SkeletonBlock(height: 10, width: 72)
                    SkeletonBlock(height: 9, width: 48)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(12)
    }
}

struct DetailPanelSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
        }
        .padding(10)
    }
}
