import SwiftUI

struct AboutView: View {
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // App header
                HStack(spacing: 16) {
                    Image(systemName: "hifispeaker.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HAPxFer")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Music file transfer for Sony HAP-Z1ES")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                Divider()

                // Why this app exists
                SectionBlock(title: "Why This App Exists", icon: "questionmark.circle") {
                    Text("The Sony HAP-Z1ES is a high-resolution music player with a built-in hard drive. Sony provided a companion app called \"HAP Music Transfer\" to copy music files from your computer to the player over the local network.")
                    Text("Sony discontinued HAP Music Transfer and it no longer works on modern macOS for two reasons:")

                    BulletPoint("SMB1 protocol removed \u{2014} macOS dropped support for SMB1 (the network file sharing protocol the HAP-Z1ES uses) starting with macOS High Sierra (2017) due to security vulnerabilities.")

                    BulletPoint("32-bit app dropped \u{2014} HAP Music Transfer was a 32-bit application. macOS Catalina (2019) removed all 32-bit app support, making the app unable to launch.")

                    Text("Sony released firmware updates and a newer version of the app, but compatibility remains broken on macOS Sonoma, Sequoia, and later. Sony has effectively end-of-lifed the HAP-Z1ES software with no further updates expected.")

                    Text("HAPxFer fills this gap as a free, open-source replacement.")
                        .fontWeight(.medium)
                        .padding(.top, 4)
                }

                // How it works
                SectionBlock(title: "How It Works", icon: "gearshape.2") {
                    Text("HAPxFer connects directly to your HAP-Z1ES over your local network using the SMB1 protocol, the same method the original Sony app used.")

                    NumberedPoint(number: 1, text: "Connect \u{2014} Enter your HAP-Z1ES's IP address. The app connects to the device's HAP_Internal share using guest authentication.")

                    NumberedPoint(number: 2, text: "Monitor \u{2014} Add folders from your Mac that contain your music library. HAPxFer watches these folders for changes.")

                    NumberedPoint(number: 3, text: "Sync \u{2014} New and modified audio files are automatically transferred to the player. Files you delete locally are also removed from the device, keeping everything in sync.")

                    NumberedPoint(number: 4, text: "Play \u{2014} The HAP-Z1ES automatically detects and analyzes new files after transfer. Your music will appear in the player's library shortly after syncing.")
                }

                // Supported formats
                SectionBlock(title: "Supported Audio Formats", icon: "music.note.list") {
                    let formats = [
                        ("DSD", "DSF, DFF (2.8/5.6 MHz)"),
                        ("Lossless", "FLAC, WAV, AIFF, ALAC"),
                        ("Lossy", "MP3, AAC/M4A"),
                        ("Other", "WMA, ATRAC (OMA, AA3)")
                    ]
                    ForEach(formats, id: \.0) { category, detail in
                        HStack(alignment: .top, spacing: 8) {
                            Text(category)
                                .fontWeight(.medium)
                                .frame(width: 70, alignment: .trailing)
                            Text(detail)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Technical details
                SectionBlock(title: "Technical Details", icon: "wrench.and.screwdriver") {
                    BulletPoint("Uses Samba's libsmbclient for SMB1 (NT1) protocol support")
                    BulletPoint("Transfers files in 64 KB chunks with real-time progress")
                    BulletPoint("Tracks sync state with a local database to enable incremental sync")
                    BulletPoint("Monitors folders via macOS FSEvents for auto-sync capability")
                    BulletPoint("Only deletes files from the device that were previously synced by this app")
                }

                Divider()

                // License
                SectionBlock(title: "License", icon: "doc.text") {
                    Text("HAPxFer is free and open-source software licensed under the GNU General Public License v3 (GPL-3.0).")
                    Text("This software uses libsmbclient from the Samba project, also licensed under GPL-3.0.")

                    Link("View source on GitHub", destination: URL(string: "https://github.com")!)
                        .padding(.top, 4)
                }

                // Disclaimer
                Text("HAPxFer is not affiliated with or endorsed by Sony Corporation. Sony, HAP-Z1ES, and HAP Music Transfer are trademarks of Sony Corporation.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(minWidth: 560, maxWidth: 640, minHeight: 500)
    }
}

// MARK: - Helper Views

private struct SectionBlock<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
                .font(.body)
        }
    }
}

private struct BulletPoint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
        }
    }
}

private struct NumberedPoint: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }
}
