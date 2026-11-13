import SwiftUI

@main
struct RoomGuardApp: App {
    @StateObject private var player = CameraPlayer()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            CameraView(player: player)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { player.setActive($0 == .active) }
        }
    }
}

private let mint = Color(red: 0.40, green: 0.88, blue: 0.71)
private let ink = Color(red: 0.047, green: 0.071, blue: 0.11)
private let panel = Color(red: 0.082, green: 0.118, blue: 0.176)

struct CameraView: View {
    @ObservedObject var player: CameraPlayer
    @State private var pairingSheet = false
    @State private var fullScreen = false
    @State private var forgetConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("RoomGuard", systemImage: "video.fill").font(.title2.bold())
                        Spacer()
                        Image(systemName: "lock.shield").foregroundStyle(mint).font(.title2)
                    }.padding(.top, 14)
                    Text("Your room, a glance away.").foregroundStyle(.secondary)
                    videoCard
                    if player.pairing == nil { onboarding }
                    else { viewerControls }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Encrypted from PC to iPhone", systemImage: "lock.fill").foregroundStyle(mint)
                        Text("Keep RoomGuard recording and your PC awake. The phone shows a live preview; full-quality recordings stay on your PC.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.footnote).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(panel, in: RoundedRectangle(cornerRadius: 18))
                }.padding(22)
            }
            .background(ink.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $pairingSheet) { PairingView(player: player) }
            .fullScreenCover(isPresented: $fullScreen) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    liveImage.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button { fullScreen = false } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).padding(20) }
                        .tint(.white).accessibilityLabel("Close full screen")
                }
            }
            .confirmationDialog("Forget this camera?", isPresented: $forgetConfirmation, titleVisibility: .visible) {
                Button("Forget camera", role: .destructive) { player.forget() }
            } message: { Text("You can pair again using the code on your PC.") }
        }
    }

    private var liveImage: some View {
        ZStack {
            Color.black
            if let image = player.image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                VStack(spacing: 12) {
                    Image(systemName: player.pairing == nil ? "video.badge.plus" : "video.slash").font(.system(size: 42, weight: .light)).foregroundStyle(mint)
                    Text(player.pairing == nil ? "Pair your PC camera" : player.status)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
                }
            }
        }
    }
    private var videoCard: some View {
        VStack(spacing: 0) {
            liveImage.aspectRatio(16 / 9, contentMode: .fit)
            HStack {
                Circle().fill(player.isLive ? mint : Color.gray).frame(width: 7, height: 7)
                Text(player.isLive ? "LIVE" : "OFFLINE").font(.caption.bold()).tracking(1)
                Spacer()
                if player.isLive { Text("\(player.receivedFPS) fps").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                Button { fullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(5) }
                    .tint(.white).accessibilityLabel("Full screen")
            }.padding(14).background(panel)
        }.clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring your camera with you").font(.title3.bold())
            Text("On your PC, open RoomGuard → Phone viewing → Enable. Then scan the pairing code here.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { pairingSheet = true } label: {
                Label("Pair camera", systemImage: "qrcode.viewfinder").font(.headline).frame(maxWidth: .infinity).padding(9)
            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
        }
    }
    private var viewerControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(player.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { player.watching ? player.stop() : player.start() } label: {
                Label(player.watching ? "Pause viewer" : "Watch live", systemImage: player.watching ? "pause.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(9)
            }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(ink)
            HStack {
                Button("Pair again") { pairingSheet = true }
                Spacer()
                Button("Forget camera", role: .destructive) { forgetConfirmation = true }
            }.font(.callout).tint(mint)
            Text("Pairing stays saved across PC restarts. Your camera reconnects when RoomGuard starts again. Only scan a new code if you reset pairing.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PairingView: View {
    @ObservedObject var player: CameraPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var scanning = false
    @State private var scannerError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { scanning = true; scannerError = nil } label: { Label("Scan PC pairing code", systemImage: "qrcode.viewfinder") }
                    Text("In RoomGuard on your PC, open Phone viewing and enable it. Keep the pairing code private.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Or paste pairing text") {
                    TextEditor(text: $text).font(.system(.footnote, design: .monospaced)).frame(minHeight: 100)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                    Button("Pair camera") { submit(text) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = scannerError ?? player.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Pair your camera")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .tint(mint)
            .sheet(isPresented: $scanning) {
                ZStack(alignment: .bottom) {
                    QRScanner(onCode: { code in scanning = false; submit(code) }, onError: { error in scannerError = error; scanning = false })
                    Button("Cancel scan") { scanning = false }.buttonStyle(.borderedProminent).padding(24).tint(.black)
                }.ignoresSafeArea()
            }
        }
    }
    private func submit(_ code: String) {
        scannerError = nil
        player.pair(code)
        if player.error == nil { text = ""; dismiss() }
    }
}
