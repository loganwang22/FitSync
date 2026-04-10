import SwiftUI
import Charts

struct TrendsView: View {
    @State var viewModel: TrendsViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Type filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            TypeChip(label: "All", isSelected: viewModel.selectedType == nil) {
                                viewModel.selectType(nil)
                            }
                            ForEach(WorkoutType.allCases) { type in
                                TypeChip(label: type.label, isSelected: viewModel.selectedType == type) {
                                    viewModel.selectType(type)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Distance Chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekly Distance")
                            .font(.headline)
                            .padding(.horizontal)

                        if viewModel.weeklyData.isEmpty || viewModel.weeklyData.allSatisfy({ $0.totalDistanceKm == 0 }) {
                            Text("No data available")
                                .foregroundStyle(.secondary)
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                        } else {
                            Chart(viewModel.weeklyData) { entry in
                                BarMark(
                                    x: .value("Week", entry.weekStart, unit: .weekOfYear),
                                    y: .value("Distance", entry.totalDistanceKm)
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                                .cornerRadius(4)
                            }
                            .chartYAxisLabel("km")
                            .frame(height: 200)
                            .padding(.horizontal)
                        }
                    }

                    // Volume Stacked Chart
                    if !viewModel.stackedData.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Volume by Sport")
                                .font(.headline)
                                .padding(.horizontal)

                            Chart(viewModel.stackedData, id: \.week) { entry in
                                BarMark(
                                    x: .value("Week", entry.week, unit: .weekOfYear),
                                    y: .value("Distance", entry.distance)
                                )
                                .foregroundStyle(by: .value("Sport", entry.type.label))
                            }
                            .chartForegroundStyleScale([
                                "Running": Color.runningColor,
                                "Cycling": Color.cyclingColor,
                                "Swimming": Color.swimmingColor,
                            ])
                            .chartYAxisLabel("km")
                            .frame(height: 200)
                            .padding(.horizontal)
                        }
                    }

                    // Duration Chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekly Duration")
                            .font(.headline)
                            .padding(.horizontal)

                        if viewModel.weeklyData.isEmpty || viewModel.weeklyData.allSatisfy({ $0.totalDurationMinutes == 0 }) {
                            Text("No data available")
                                .foregroundStyle(.secondary)
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                        } else {
                            Chart(viewModel.weeklyData) { entry in
                                BarMark(
                                    x: .value("Week", entry.weekStart, unit: .weekOfYear),
                                    y: .value("Duration", entry.totalDurationMinutes)
                                )
                                .foregroundStyle(Color.green.gradient)
                                .cornerRadius(4)
                            }
                            .chartYAxisLabel("min")
                            .frame(height: 200)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Trends")
            .onAppear { viewModel.load() }
        }
    }
}

private struct TypeChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
