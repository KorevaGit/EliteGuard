import SwiftUI

@main
struct EliteGuardApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.open(url: $0) }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.signedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: model.signedIn)
        .sheet(item: $model.pairRequest) { request in
            PairFlowView(request: request)
        }
        .alert("EliteGuard", isPresented: Binding(
            get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
    }
}
