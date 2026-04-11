import SwiftUI

struct WorkoutIcon: View {
    let type: WorkoutType
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: type.systemImage)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(type.color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

struct StatLabel: View {
    let title: String
    let value: String
    let icon: String?

    init(_ title: String, value: String, icon: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let icon {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline)
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}
