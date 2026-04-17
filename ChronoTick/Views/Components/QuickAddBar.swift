import SwiftUI

struct QuickAddBar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            TextField("快速输入：例如 23:30 ~ 23:50 read book", text: $viewModel.quickEntryText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await viewModel.createTaskFromQuickInput(modelContext: modelContext) }
                }
            Button("添加") {
                Task { await viewModel.createTaskFromQuickInput(modelContext: modelContext) }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
