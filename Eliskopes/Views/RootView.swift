import SwiftUI

/// The app's one navigation stack: the projects list, then a project's package screen, then one of its 10 buttons.
struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            ProjectsIndexView { path = [.project($0)] }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .project(let id): ProjectView(projectID: id, path: $path)
                    case .field(let field): FieldScreen(field: field, path: $path)
                    }
                }
        }
        .overlay(alignment: .top) { NoticeBanner() }
    }
}

/// Every project in the bidding rounds, open ones first. Tapping one opens its packages.
struct ProjectsIndexView: View {
    @Environment(ProjectStore.self) private var store
    @State private var showAccount = false
    let open: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Projects")
                if store.projects.isEmpty {
                    if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        Text("No projects yet. Eliskopes staff publish each project before its bidding round opens.")
                            .font(Theme.sans(15)).foregroundStyle(Theme.slate)
                    }
                }
                ForEach(store.projects) { project in
                    Button { open(project.id) } label: {
                        ProjectRow(project: project, featured: project.id == store.featuredProjectID)
                    }
                    .buttonStyle(.plain)
                }
                if store.isDemo {
                    NoteRow(symbol: "info.circle",
                            text: "Demo mode: Firebase isn’t connected, so this is the sample project from eliskopes.com. Tap the person icon to sign in as a bidder, the owner or staff.")
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .refreshable { await store.refreshProjects() }
        .background(Theme.page)
        .overlay(alignment: .bottom) { ErrorBanner() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showAccount = true } label: {
                    Image(systemName: store.user == nil ? "person.crop.circle" : "person.crop.circle.fill")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Account")
            }
            ToolbarItem(placement: .principal) { BrandTitle() }
        }
        .navBarStyle()
        .sheet(isPresented: $showAccount) { AccountView() }
    }
}

struct BrandTitle: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .foregroundStyle(Theme.amber)
            Text("ELISKOPES")
                .font(Theme.sans(17, .bold))
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Eliskopes")
    }
}

private struct ProjectRow: View {
    let project: Project
    let featured: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.round.uppercased())
                        .font(Theme.mono(11, .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.orange)
                    if project.isOpen {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.greenDot).frame(width: 7, height: 7)
                            Text("LIVE").font(Theme.mono(10, .bold))
                        }
                        .foregroundStyle(Theme.green)
                    } else {
                        Text("AWARDED").font(Theme.mono(10, .bold)).foregroundStyle(Theme.muted)
                    }
                }
                Text(project.name)
                    .font(Theme.sans(18, .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text("\(project.city) · \(project.isOpen ? "closes" : "closed") \(project.closesAt.centralText)")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.slate)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(featured ? Theme.amber : Theme.line))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBanner: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        if let message = store.errorMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(message).font(Theme.sans(14)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Button { store.errorMessage = nil } label: { Image(systemName: "xmark").foregroundStyle(Theme.mist) }
                    .accessibilityLabel("Dismiss")
            }
            .padding(14)
            .background(Theme.navyCard, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)
        }
    }
}

/// Bid placed, outbid, question posted: slides in at the top for five seconds.
struct NoticeBanner: View {
    @Environment(ProjectStore.self) private var store

    var body: some View {
        Group {
            if let notice = store.notice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.fill").foregroundStyle(Theme.amber)
                    Text(notice).font(Theme.sans(14, .medium)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Theme.navy, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber))
                .padding(.horizontal, 16)
                .padding(.top, 52)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.notice = nil }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: store.notice)
        .task(id: store.notice) {
            guard store.notice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { store.notice = nil }
        }
    }
}

extension View {
    /// The navy bar every screen uses.
    func navBarStyle() -> some View {
        toolbarBackground(Theme.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    let store = ProjectStore(backend: SampleBackend())
    return RootView()
        .environment(store)
        .task { await store.start() }
}
