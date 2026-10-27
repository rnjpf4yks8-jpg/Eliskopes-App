import SwiftUI

/// One button's content on its own pushed screen. Back returns to the package screen;
/// the bar at the bottom moves to the previous or next button's screen.
struct FieldScreen: View {
    @Environment(ProjectStore.self) private var store
    let field: PackageField
    @Binding var path: [Route]
    @State private var asking = false
    @State private var addingDocument = false

    var body: some View {
        Group {
            if let package = store.currentPackage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "\(package.code) · \(package.name)")
                            Text("\(store.project?.name ?? "") · \(store.project?.city ?? "")")
                                .font(Theme.sans(14))
                                .foregroundStyle(Theme.slate)
                        }
                        FieldContent(field: field, package: package)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                ContentUnavailableView("No package selected", systemImage: "shippingbox")
            }
        }
        .background(Theme.page)
        .overlay(alignment: .bottom) { ErrorBanner() }
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
        .navBarStyle()
        .toolbar {
            if field == .questions, store.canAsk {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ask") { asking = true }
                        .foregroundStyle(Theme.amber)
                }
            }
            if field == .documents, store.isStaff, store.currentPackage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add PDF") { addingDocument = true }
                        .foregroundStyle(Theme.amber)
                }
            }
        }
        .sheet(isPresented: $asking) { AskSheet() }
        .sheet(isPresented: $addingDocument) { DocumentSheet(replacing: nil) }
        .safeAreaInset(edge: .bottom) { pager }
    }

    private var pager: some View {
        HStack {
            pagerButton(field.previous, leading: true)
            Spacer()
            Text("\(field.rawValue + 1) / \(PackageField.allCases.count)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
            Spacer()
            pagerButton(field.next, leading: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder
    private func pagerButton(_ target: PackageField?, leading: Bool) -> some View {
        Button {
            guard let target, !path.isEmpty else { return }
            path[path.count - 1] = .field(target)
        } label: {
            HStack(spacing: 6) {
                if leading { Image(systemName: "chevron.left") }
                Text(target?.title ?? "")
                if !leading { Image(systemName: "chevron.right") }
            }
            .font(Theme.sans(15, .semibold))
            .frame(minWidth: 110, minHeight: 44, alignment: leading ? .leading : .trailing)
        }
        .disabled(target == nil)
        .opacity(target == nil ? 0 : 1)
    }
}
