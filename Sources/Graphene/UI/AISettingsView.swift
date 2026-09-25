import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var skills: SkillStore
    @StateObject private var memory: MemoryStore
    @State private var pendingProvider: ProviderKind?
    @State private var consent = false
    @State private var key = ""
    @State private var status = ""
    @State private var edit: ChatSkill?
    init(root: URL) { _skills = StateObject(wrappedValue: SkillStore(root: root)); _memory = StateObject(wrappedValue: MemoryStore(root: root)) }
    private var settings: AISettings { app.settings.ai ?? AISettings() }
    private func binding<T>(_ path: WritableKeyPath<AISettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: path] }, set: { value in var copy = settings; copy[keyPath: path] = value; app.settings.ai = copy; app.persist() })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Model provider", selection: Binding(get: { settings.provider }, set: { provider in
                key = ""
                if provider != .onDevice && !settings.remoteConsent { pendingProvider = provider; consent = true }
                else { binding(\.provider).wrappedValue = provider }
            })) { ForEach(ProviderKind.allCases, id: \.self) { Text($0.title).tag($0) } }
            Text(app.providerRegistry.unavailableReason ?? "Ready. Browsing and source search never require a model.").foregroundStyle(app.pal.ink2)
            if settings.provider == .compatible {
                TextField("API base URL", text: binding(\.baseURL)).textFieldStyle(.roundedBorder)
                TextField("Model", text: binding(\.model)).textFieldStyle(.roundedBorder)
                Text("OpenAI, OpenRouter, or Ollama at http://localhost:11434/v1. HTTP is allowed only on loopback.").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            }
            if settings.provider == .anthropic { TextField("Model", text: binding(\.anthropicModel)).textFieldStyle(.roundedBorder) }
            if settings.provider != .onDevice {
                SecureField("API key (stored only in Keychain)", text: $key).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save API key") {
                        do {
                            let account = app.providerRegistry.keyAccount
                            try Keychain.saveAIKey(key, account: account)
                            guard Keychain.aiKey(account: account) == key else { status = "Keychain verification failed."; return }
                            key = ""; status = "API key saved and verified in Keychain."
                        } catch { status = error.localizedDescription }
                    }.disabled(key.isEmpty)
                    Button("Remove key") {
                        do { let account = app.providerRegistry.keyAccount; try Keychain.saveAIKey("", account: account); status = Keychain.aiKey(account: account) == nil ? "Key removed." : "Key removal could not be verified." } catch { status = error.localizedDescription }
                    }
                }
                Text("Attached pages, drafts and conversation turns go to the selected endpoint only when you ask. Switch to Apple to keep generation on this Mac.").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            }
            if !status.isEmpty { Text(status).font(.system(size: 11)) }
            Divider()
            Toggle("Personal context", isOn: binding(\.personalContext))

            Text("Off by default. When enabled, after each completed answer the selected model extracts up to three explicitly stated preferences or projects from your messages, not page text. Stored locally in memory.json, scoped to this profile, and sent as context in later chats. Turning off stops extraction and use, but keeps the editable list below.").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            ForEach($memory.items) { $item in
                if item.profileID == (app.activeSpace.profileID ?? Profile.defaultID) {
                    HStack {
                        TextField("Personal fact", text: $item.text).onSubmit { memory.save() }
                        Button("Save") { memory.save() }
                        Button { memory.items.removeAll { $0.id == item.id }; memory.save() } label: { Image(systemName: "trash") }.accessibilityLabel("Delete personal fact")
                    }
                }
            }
            Button("Clear this profile’s personal context") { memory.items.removeAll { $0.profileID == (app.activeSpace.profileID ?? Profile.defaultID) }; memory.save() }
            if let error = memory.error { Text(error) }
            Divider()
            Toggle("Tidy pinned tab titles", isOn: Binding(get: { settings.tidyTitles == true }, set: { binding(\.tidyTitles).wrappedValue = $0 }))
            Toggle("Suggest tidy download names", isOn: Binding(get: { settings.tidyDownloads == true }, set: { binding(\.tidyDownloads).wrappedValue = $0 }))
            Text("Tidy titles sends a pinned page’s title once per URL. Tidy downloads sends only the finished filename, never file contents, and asks before renaming. Both require a model.").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            Divider()
            Text("Skills").font(.headline)
            Text("Prompt templates with explicit context. A model is required to run them.").font(.system(size: 11)).foregroundStyle(app.pal.ink3)
            ForEach(skills.skills) { skill in
                HStack {
                    VStack(alignment: .leading) { Text(skill.name); Text(skill.trigger + " · " + skill.contexts.map(\.rawValue).joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(app.pal.ink3) }
                    Spacer()
                    Button("Edit") { edit = skill }
                    Button("Duplicate") { var copy = skill; copy.id = UUID(); copy.name += " copy"; copy.trigger += "-copy"; edit = copy }
                    Button { skills.skills.removeAll { $0.id == skill.id }; skills.save() } label: { Image(systemName: "trash") }.accessibilityLabel("Delete \(skill.name)")
                }
            }
            Button("Add skill") { edit = ChatSkill(name: "New skill", trigger: "/new", instructions: "", contexts: [.currentTab]) }
            if let error = skills.error { Text(error) }
        }.sheet(isPresented: $consent) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Use an external model?").font(.headline)
                Text("When you ask, Graphene will send your attached page text, writing drafts, questions, relevant conversation turns and enabled personal context to the endpoint you select. Its privacy and retention policies apply. Ollama on localhost stays on your machine. Private, excluded and other-profile sources are never attached. Browsing does not require this.")
                HStack {
                    Button("Keep on device") { consent = false; pendingProvider = nil }
                    Spacer()
                    Button("Use selected provider") { var copy = settings; copy.remoteConsent = true; copy.provider = pendingProvider ?? .onDevice; app.settings.ai = copy; app.persist(); consent = false }
                }
            }.padding(24).frame(width: 460)
        }.sheet(item: $edit) { skill in
            SkillEditor(skill: skill, existing: skills.skills) { value in
                skills.skills.removeAll { $0.id == value.id }; skills.skills.append(value); skills.save(); edit = nil
            }
        }
    }
}
private struct SkillEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var skill: ChatSkill
    let existing: [ChatSkill]
    let save: (ChatSkill) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit skill").font(.headline)
            TextField("Name", text: $skill.name)
            TextField("/trigger", text: $skill.trigger)
            TextEditor(text: $skill.instructions).frame(height: 130).overlay { RoundedRectangle(cornerRadius: 8).stroke(app.pal.hairline) }
            ForEach(ChatSkill.Context.allCases, id: \.self) { context in
                Toggle(context.rawValue, isOn: Binding(get: { skill.contexts.contains(context) }, set: { if $0 { skill.contexts.append(context) } else { skill.contexts.removeAll { $0 == context } } }))
            }
            HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") { save(skill) }.disabled(!skill.valid || existing.contains { $0.id != skill.id && $0.trigger == skill.trigger }) }
        }.padding(24).frame(width: 440).foregroundStyle(app.pal.ink).background(app.pal.ground)
    }
}
