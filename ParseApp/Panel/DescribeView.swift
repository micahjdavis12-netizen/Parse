import SwiftUI

struct DescribeView: View {
    @Bindable var session: SessionStore

    var body: some View {
        PairedTranslationView(session: session, mode: .editing)
    }
}
