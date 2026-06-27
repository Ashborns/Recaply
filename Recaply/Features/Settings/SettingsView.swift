import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @AppStorage("recaply_on_device_speech") private var onDeviceSpeech = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    apiKeysCard
                    speechCard
                    aboutCard
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { vm.save() }
                        .foregroundColor(.accentCyan)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recaply AI")
                .font(.largeTitle.bold())
                .foregroundColor(.textPrimary)
            Text("Configure secure cloud enhancement and on-device speech preferences.")
                .foregroundColor(.textSecondary)
        }
    }

    private var apiKeysCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Cloud LLM")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                SecureField("GLM API key", text: $vm.glmKey)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                SecureField("Deepseek fallback API key", text: $vm.deepseekKey)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                Picker("Model route", selection: $vm.selectedModel) {
                    Text("GLM primary + Deepseek fallback").tag("GLM primary + Deepseek fallback")
                    Text("Deepseek fallback only").tag("Deepseek fallback only")
                }
                .pickerStyle(.menu)
                .foregroundColor(.textPrimary)

                if let message = vm.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(vm.hasAnyKey ? .catDecision : .catAction)
                } else if !vm.hasAnyKey {
                    Text("No key saved yet. Recording and on-device transcription still work; summaries are skipped until you add a key.")
                        .font(.footnote)
                        .foregroundColor(.textTertiary)
                }
            }
        }
    }

    private var speechCard: some View {
        glassCard {
            Toggle(isOn: $onDeviceSpeech) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prefer on-device speech")
                        .foregroundColor(.textPrimary)
                    Text("Keeps transcription private when the device supports it.")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
            }
            .tint(.accentPurple)
        }
    }

    private var aboutCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("Recaply records meetings and lectures, transcribes them on-device, classifies sentence intent with CoreML, then enhances summaries through your configured LLM provider.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.glassStroke, lineWidth: 1)
            )
    }
}
