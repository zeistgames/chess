import SwiftUI

/// Signing in to Zeist: a sheet from the bottom, opened by the button that asked for it.
struct SignInSheet: View {
    @State private var account = Account.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sign in to Zeist").font(Z.title(30, relativeTo: .title)).padding(.bottom, 8)
            Text("Sign in to Zeist to keep a rating and records.").font(Z.text(15.5)).foregroundStyle(Z.soft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                Button { go("apple") } label: {
                    HStack(spacing: 8) { Image(systemName: "apple.logo").font(.system(size: 17, weight: .medium)); Text("Continue with Apple") }
                }
                .buttonStyle(Pill(solid: true, wide: true))
                .accessibilityIdentifier("sign-in-apple")
                Button { go("google") } label: { Text("Continue with Google") }
                    .buttonStyle(Pill(wide: true))
                    .accessibilityIdentifier("sign-in-google")
            }
            .disabled(account.busy)
            .padding(.top, 24)
            if let p = account.problem { Text(p).font(Z.text(14)).foregroundStyle(Z.soft).padding(.top, 12) }
            Text(terms).font(Z.text(13)).foregroundStyle(Z.dim).tint(Z.soft)
                .padding(.top, 18).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Z.ink)
        .presentationBackground(Z.raised)
        .presentationDetents([.height(330)])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
        .onChange(of: account.signedIn) { _, on in if on { dismiss() } }
    }

    private var terms: AttributedString {
        var s = (try? AttributedString(markdown: "Signing in means you agree to Zeist's [Terms](https://\(Hosts.primary)/terms) and [Privacy](https://\(Hosts.primary)/privacy).")) ?? AttributedString("Signing in means you agree to Zeist's Terms and Privacy.")
        for run in s.runs where run.link != nil { s[run.range].underlineStyle = .single }
        return s
    }

    private func go(_ provider: String) {
        Feel.shared.select()
        Task { await account.signIn(provider) }
    }
}

/// The quiet line and its one button, where signing in is offered.
struct SignInLine: View {
    @State private var account = Account.shared
    @State private var open = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Sign in to Zeist to keep a rating and records.").font(Z.text(15)).foregroundStyle(Z.soft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(account.busy ? "Signing in" : "Sign in") { Feel.shared.select(); open = true }
                .buttonStyle(Pill(small: true))
                .disabled(account.busy)
                .accessibilityIdentifier("sign-in")
        }
        .sheet(isPresented: $open) { SignInSheet() }
    }
}
