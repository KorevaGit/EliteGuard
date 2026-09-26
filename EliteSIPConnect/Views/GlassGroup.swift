import SwiftUI

/// One glass surface for a whole form section. Rows keep their dividers inside it.
struct GlassGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .buttonStyle(.borderless)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

struct GlassRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

struct GlassDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}
