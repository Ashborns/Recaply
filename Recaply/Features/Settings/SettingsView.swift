import SwiftUI

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @AppStorage(SpeechRecognitionPreferences.preferOnDeviceKey) private var onDeviceSpeech = false
    @AppStorage(RecaplySpeechLanguage.defaultsKey) private var speechLanguageRaw = RecaplySpeechLanguage.automatic.rawValue

    private var selectedSpeechLanguage: RecaplySpeechLanguage {
        RecaplySpeechLanguage(rawValue: speechLanguageRaw) ?? .automatic
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    workflowCard
                    modesCard
                    modelCard
                    aiCard
                    speechCard
                    exportCard
                    aboutCard
                }
                .padding(20)
                .padding(.top, 12)
                .padding(.bottom, 130)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.largeTitle.bold())
                .foregroundColor(.textPrimary)
            Text("Control what Recaply produces after every recording.")
                .foregroundColor(.textSecondary)
        }
    }

    private var workflowCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Output Pipeline")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                settingRow("1", "Live captions", "Shows rough text while recording.")
                settingRow("2", "CoreML labels", "Detects actions, decisions, questions, and discussion.")
                settingRow("3", "AI recap", "Generates overview, key points, and polished notes.")
            }
        }
    }

    private var modesCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recording Modes")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                modeRow(.meeting)
                modeRow(.lecture)
            }
        }
    }

    private var aiCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: vm.hasAnyAIProviderConfigured ? "checkmark.seal.fill" : "bolt.trianglebadge.exclamationmark.fill")
                        .foregroundColor(vm.hasAnyAIProviderConfigured ? .catDecision : .catAction)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.06), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Summary Engine")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(vm.aiEngineDescription)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    Spacer()
                    Text(vm.hasAnyAIProviderConfigured ? "Connected" : "Offline")
                        .font(.caption.bold())
                        .foregroundColor(vm.hasAnyAIProviderConfigured ? .catDecision : .catAction)
                }

                VStack(spacing: 10) {
                    ForEach(vm.aiProviderDiagnostics) { diagnostic in
                        aiProviderRow(diagnostic)
                    }
                }

                Text("Used only after recording to improve summaries and polished notes. If the main AI/server fails, Recaply tries Groq and then local fallback while showing a warning in the app.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)

                Text("Security check: masked keys are shown only for local diagnostics. Production builds should not expose bundled `.env` keys to users.")
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private func aiProviderRow(_ diagnostic: SettingsViewModel.AIProviderDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: diagnostic.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(diagnostic.isConfigured ? .catDecision : .catAction)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(diagnostic.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.textPrimary)
                    Text(diagnostic.role)
                        .font(.caption2.bold())
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    Spacer(minLength: 0)
                }

                Text("Model: \(diagnostic.modelName)")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                HStack(spacing: 8) {
                    Text(diagnostic.maskedKey)
                        .font(.caption.monospaced())
                        .foregroundColor(diagnostic.isConfigured ? .textSecondary : .textTertiary)
                    Text(diagnostic.source)
                        .font(.caption2.bold())
                        .foregroundColor(diagnostic.isProductionSafe ? .catDecision : (diagnostic.isConfigured ? .catAction : .textTertiary))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            (diagnostic.isProductionSafe ? Color.catDecision : (diagnostic.isConfigured ? Color.catAction : Color.white)).opacity(0.10),
                            in: Capsule()
                        )
                }

                Text(diagnostic.securityNote)
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(12)
        .background(Color.surfaceDeep.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.glassStroke, lineWidth: 1))
    }

    private var modelCard: some View {
        glassCard {
            HStack(spacing: 12) {
                Image(systemName: vm.isClassifierAvailable ? "brain.head.profile" : "exclamationmark.triangle.fill")
                    .foregroundColor(vm.isClassifierAvailable ? .catDecision : .catAction)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("CoreML Classifier")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(vm.isClassifierAvailable ? "ActionItemClassifier is installed and ready." : "Model missing. Sentence labels will fall back to discussion.")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Text(vm.isClassifierAvailable ? "Ready" : "Missing")
                    .font(.caption.bold())
                    .foregroundColor(vm.isClassifierAvailable ? .catDecision : .catAction)
            }
        }
    }

    private var speechCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription Language")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(selectedSpeechLanguage.caption)
                        .font(.caption)
                        .foregroundColor(.textTertiary)

                    Picker("Language", selection: $speechLanguageRaw) {
                        ForEach(RecaplySpeechLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.accentCyan)
                }

                Divider().overlay(Color.glassStroke)

                Toggle(isOn: $onDeviceSpeech) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prefer on-device speech")
                            .foregroundColor(.textPrimary)
                        Text("Keep this off for better multilingual reliability. Turn it on only when the chosen language is available offline.")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }
                .tint(.accentPurple)
            }
        }
    }

    private var exportCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Export & Portability")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("Every detail page can export clean notes as `.txt` and full structured data as `.json` for reports, backup, or grading evidence.")
                    .font(.footnote)
                    .foregroundColor(.textSecondary)
            }
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
            .background(Color.surfaceRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.glassStroke, lineWidth: 1)
            )
    }

    private func settingRow(_ badge: String, _ title: String, _ body: String) -> some View {
        HStack(spacing: 12) {
            Text(badge)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private func modeRow(_ tag: SessionTag) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tag.iconName)
                .foregroundColor(tag == .meeting ? .accentPurple : .accentCyan)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.06), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(tag.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                Text(tag.shortDescription)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
        }
    }
}
