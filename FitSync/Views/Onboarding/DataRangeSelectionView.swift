import SwiftUI

struct DataRangeSelectionView: View {
    let onSelect: (Int) -> Void

    private let options: [(label: String, months: Int)] = [
        ("1 Month", 1),
        ("3 Months", 3),
        ("6 Months", 6),
        ("1 Year", 12),
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Workout History")
                .font(.largeTitle.bold())

            Text("How far back should FitSync load your workout data?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                ForEach(options, id: \.months) { option in
                    Button {
                        onSelect(option.months)
                    } label: {
                        Text(option.label)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer().frame(height: 32)
        }
    }
}
