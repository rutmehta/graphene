import SwiftUI
import WebKit

struct ProfileSettings: View {
    @EnvironmentObject var app: AppState
    @State private var name = ""
    @State private var icon = "person.crop.circle"
    @State private var deleting: Profile?
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profiles isolate website cookies, logins and storage. Threads and Vault remain in your shared local library. Existing tabs adopt a changed space profile after restarting Graphene.").foregroundStyle(app.pal.ink2)
            Label("Default", systemImage: "person.crop.circle")
            ForEach(app.profiles) { profile in
                HStack {
                    Image(systemName: profile.icon)
                    TextField("Name", text: Binding(get: { app.profiles.first { $0.id == profile.id }?.name ?? profile.name }, set: { value in
                        if let i = app.profiles.firstIndex(where: { $0.id == profile.id }) { app.profiles[i].name = value; app.persist() }
                    }))
                    Button("Delete…", role: .destructive) { deleting = profile }
                }
            }
            HStack {
                TextField("New profile name", text: $name).textFieldStyle(.roundedBorder)
                Picker("Icon", selection: $icon) { ForEach(["person.crop.circle", "briefcase", "house", "flask"], id: \.self) { Image(systemName: $0).tag($0) } }.frame(width: 120)
                Button("Add") { app.profiles.append(Profile(name: name.trimmingCharacters(in: .whitespaces), icon: icon)); app.persist(); name = "" }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            ForEach(app.spaces) { space in
                Picker(space.name, selection: Binding(get: { app.spaces.first { $0.id == space.id }?.profileID ?? Profile.defaultID }, set: { id in
                    if let index = app.spaces.firstIndex(where: { $0.id == space.id }) { app.spaces[index].profileID = id == Profile.defaultID ? nil : id; app.persist() }
                })) {
                    Text("Default").tag(Profile.defaultID)
                    ForEach(app.profiles) { Text($0.name).tag($0.id) }
                }
            }
            if !status.isEmpty { Text(status) }
        }.confirmationDialog("Delete profile and its website data?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete profile", role: .destructive) {
                guard let profile = deleting else { return }
                deleting = nil
                for index in app.spaces.indices where app.spaces[index].profileID == profile.id { app.spaces[index].profileID = nil }
                for tab in app.tabs where tab.profileID == profile.id { tab.discard(); tab.profileID = Profile.defaultID }
                let storeID = Profile.storeID(profile.id, namespace: ProcessInfo.processInfo.environment["GRAPHENE_DATA_DIR"])
                WKWebsiteDataStore.remove(forIdentifier: storeID) { error in
                    Task { @MainActor in
                        if let error { status = "Couldn’t remove website data: \(error.localizedDescription)" }
                        else { app.profiles.removeAll { $0.id == profile.id }; app.persist(); status = "Profile and website data removed." }
                    }
                }
            }
        } message: { Text("This signs you out and resets assigned spaces to Default. Tabs and saved knowledge are kept.") }
    }
}
