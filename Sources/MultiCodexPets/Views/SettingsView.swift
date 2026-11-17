import AppKit
import MultiCodexPetsCore
import SwiftUI

enum PetBehaviorMode: String, CaseIterable {
  case sessions = "Follow Agent Sessions"
  case walking = "Walk Around"
  case manual = "Manual Animation"
}

enum SettingsTab { case pets, behavior, sessions }

private struct PetSettingsSheet: Identifiable {
  enum Kind: String { case sounds, animations, nameLabel }
  let pet: PetPackage
  let kind: Kind
  var id: String { "\(kind.rawValue):\(pet.id)" }
}

struct SettingsView: View {
  @ObservedObject var app: AppDelegate
  @State private var selectedTab = SettingsTab.pets
  @State private var petSheet: PetSettingsSheet?
  @State private var renamingPet: PetPackage?
  @State private var petName = ""
  @State private var search = ""
  @State private var showsCompleted = false
  @State private var assignmentPetID = ""
  @State private var agentFilter: AgentSession?

  private var uiScale: CGFloat { app.settingsLayout.scale }
  private var bodyFont: Font { .system(size: 15 * uiScale) }
  private var detailFont: Font { .system(size: 13 * uiScale) }
  private var headingFont: Font { .system(size: 17 * uiScale, weight: .semibold) }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 16 * uiScale) {
        HStack(spacing: 4 * uiScale) {
          settingsTab(.pets, title: "Pets", symbol: "pawprint")
          settingsTab(.behavior, title: "Behavior", symbol: "play.circle")
          settingsTab(.sessions, title: "Sessions", symbol: "terminal")
        }
        .padding(4 * uiScale)
        .background(
          Color(nsColor: .controlBackgroundColor),
          in: RoundedRectangle(cornerRadius: 12 * uiScale, style: .continuous))
        Group {
          switch selectedTab {
          case .pets: pets
          case .behavior: behavior
          case .sessions: sessions
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .padding(20 * uiScale)
      Divider()
      HStack {
        Text(localized("Changes apply immediately."))
          .font(bodyFont).foregroundStyle(.secondary)
        Spacer()
        Button(localized("Done")) { NSApp.keyWindow?.close() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(20 * uiScale)
    }
    .font(bodyFont)
    .controlSize(.large)
    .frame(
      minWidth: min(600, app.settingsLayout.minimumContentSize.width),
      minHeight: min(480, app.settingsLayout.minimumContentSize.height)
    )
    .onReceive(app.$requestedSettingsPetID) { id in
      guard let id else { return }
      selectedTab = .sessions
      assignmentPetID = id
    }
    .onReceive(app.$requestedNameLabelPetID) { id in
      guard let id, let pet = app.petPackages.first(where: { $0.id == id }) else { return }
      selectedTab = .pets
      renamingPet = nil
      petSheet = PetSettingsSheet(pet: pet, kind: .nameLabel)
    }
    .sheet(item: $petSheet, onDismiss: { app.requestedNameLabelPetID = nil }) { sheet in
      switch sheet.kind {
      case .sounds: PetSoundSettingsView(app: app, pet: sheet.pet)
      case .animations: PetAnimationSettingsView(app: app, pet: sheet.pet)
      case .nameLabel: PetNameLabelSettingsView(app: app, pet: sheet.pet)
      }
    }
    .alert(
      localized("Rename Pet"),
      isPresented: Binding(
        get: { renamingPet != nil }, set: { if !$0 { renamingPet = nil } }),
      presenting: renamingPet
    ) { pet in
      TextField(localized("Pet Name"), text: $petName)
      Button(localized("Save")) {
        app.renamePet(pet.id, to: petName)
      }
      .disabled(petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button(localized("Use Original Name")) {
        app.renamePet(pet.id, to: "")
      }
      Button(localized("Cancel"), role: .cancel) {}
    } message: { _ in
      Text(localized("Only the display name changes. Files and session assignments stay the same."))
    }
  }

  private func settingsTab(_ tab: SettingsTab, title: String, symbol: String) -> some View {
    Button {
      selectedTab = tab
    } label: {
      Label(localized(title), systemImage: symbol)
        .font(bodyFont.weight(.medium))
        .frame(maxWidth: .infinity, minHeight: 46 * uiScale)
        .contentShape(Rectangle())
        .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
        .background(
          selectedTab == tab ? Color.accentColor : Color.clear,
          in: RoundedRectangle(cornerRadius: 8 * uiScale, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(localized(title))
    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
  }

  private var pets: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 5 * uiScale) {
          Text(localized("Choose Your Pets")).font(.system(size: 22 * uiScale, weight: .semibold))
          Text(
            localizedFormat(
              "%d selected · %d available", app.selectedPetIDs.count, app.petPackages.count)
          )
          .font(detailFont).foregroundStyle(.secondary)
        }
        Spacer()
        Button(localized("Select All"), action: app.selectAllPets)
        Button(localized("Clear"), action: app.clearVisiblePets)
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if app.petPackages.isEmpty {
            Text(localized("No pets found. Open the custom pet folder to add a pet, then refresh."))
              .foregroundStyle(.secondary)
          }
          ForEach([PetSource.codexDefault, .custom], id: \.self) { source in
            let packages = app.petPackages.filter { $0.source == source }
            if !packages.isEmpty {
              Text(localized(source == .codexDefault ? "Codex Defaults" : "Custom Pets"))
                .font(headingFont).padding(.top, 4)
              LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10 * uiScale), count: 3),
                spacing: 10 * uiScale
              ) {
                ForEach(packages, id: \.id) { pet in petTile(pet) }
              }

            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(4)
      }
      Text(
        localized(
          "Set click and notification sounds for each pet. Multiple selected sounds play randomly.")
      )
      .font(detailFont).foregroundStyle(.secondary)
      Divider()
      HStack {
        Button(localized("Open Custom Pet Folder…"), action: app.openPetFolder)
        Spacer()
        Button(localized("Recover Pets"), action: app.recoverPetPositions)
        Button(localized("Refresh Pets"), action: app.refreshPetsAction)
      }
    }
    .padding(8 * uiScale)
  }

  private func petTile(_ pet: PetPackage) -> some View {
    let selected = app.selectedPetIDs.contains(pet.id)
    return VStack(alignment: .leading, spacing: 8 * uiScale) {
      HStack(spacing: 6 * uiScale) {
        Toggle(
          app.displayName(for: pet),
          isOn: Binding(
            get: { app.selectedPetIDs.contains(pet.id) }, set: { _ in app.toggleVisiblePet(pet.id) }
          )
        )
        .font(bodyFont.weight(.medium)).lineLimit(1).help(app.displayName(for: pet))
        if app.settings.petPreferences[pet.id]?.positionLocked == true {
          Image(systemName: "lock.fill").font(detailFont).foregroundStyle(.secondary)
            .accessibilityLabel(localized("Lock Position"))
        }
        if app.settings.petPreferences[pet.id]?.muted == true {
          Image(systemName: "speaker.slash.fill").font(detailFont).foregroundStyle(.secondary)
            .accessibilityLabel(localized("Mute This Pet"))
        }
        if pet.spriteVersion == .v2 {
          Text("V2").font(.system(size: 12 * uiScale, weight: .semibold))
            .padding(.horizontal, 8 * uiScale).padding(.vertical, 4 * uiScale)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .help(localized("Supports cursor tracking"))
        }
      }
      Button {
        app.toggleVisiblePet(pet.id)
      } label: {
        Group {
          if let image = app.previewImage(for: pet) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
          } else {
            Image(systemName: "pawprint").resizable().scaledToFit().foregroundStyle(.secondary)
          }
        }
        .frame(width: 84 * uiScale, height: 92 * uiScale)
        .padding(4 * uiScale).frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(localizedFormat(selected ? "Hide %@" : "Show %@", app.displayName(for: pet)))
      Text(
        localizedFormat(
          "Click: %d · Alerts: %d", app.sounds(for: pet.id, role: .click).count,
          app.sounds(for: pet.id, role: .notification).count)
      )
      .font(detailFont).foregroundStyle(.secondary).lineLimit(1)
      HStack(spacing: 6 * uiScale) {
        Button {
          petSheet = PetSettingsSheet(pet: pet, kind: .animations)
        } label: {
          Label(localized("Animations…"), systemImage: "play.rectangle").font(detailFont)
            .frame(maxWidth: .infinity, minHeight: 26 * uiScale)
        }
        .accessibilityLabel(localizedFormat("Preview animations for %@", app.displayName(for: pet)))
        Button {
          petSheet = PetSettingsSheet(pet: pet, kind: .sounds)
        } label: {
          Label(localized("Sounds…"), systemImage: "waveform").font(detailFont)
            .frame(maxWidth: .infinity, minHeight: 26 * uiScale)
        }
        .accessibilityLabel(localizedFormat("Choose sound for %@", app.displayName(for: pet)))
        Menu {
          Button(localized("Rename Pet…")) {
            petName = app.displayName(for: pet)
            renamingPet = pet
          }
          Button(localized("Name Label…")) { petSheet = PetSettingsSheet(pet: pet, kind: .nameLabel) }
          Divider()
          Toggle(
            localized("Lock Position"),
            isOn: Binding(
              get: { app.settings.petPreferences[pet.id]?.positionLocked ?? false },
              set: { app.setPetPreference(pet.id, locked: $0) }))
          Toggle(
            localized("Mute This Pet"),
            isOn: Binding(
              get: { app.settings.petPreferences[pet.id]?.muted ?? false },
              set: { app.setPetPreference(pet.id, muted: $0) }))
          Button(localized("Open Sound Folder…")) { app.openSoundFolder(pet.id) }
          Divider()
          Menu(localized("Move to Display")) {
            ForEach(app.availableScreens, id: \.id) { screen in
              Button(screen.name) { app.movePet(pet.id, to: screen.id) }
            }
          }
        } label: {
          Image(systemName: "ellipsis").frame(width: 32 * uiScale, height: 32 * uiScale)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(localized("Pet Options"))

      }
    }
    .padding(12 * uiScale)
    .background(
      selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor),
      in: RoundedRectangle(cornerRadius: 12 * uiScale, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12 * uiScale, style: .continuous)
        .strokeBorder(
          selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 1)
    )
  }

  private var behavior: some View {
    Form {
      Section {
        LabeledContent(localized("Mode")) {
          Menu {
            ForEach(PetBehaviorMode.allCases, id: \.self) { mode in
              Button(localized(mode.rawValue)) { app.setBehaviorMode(mode) }
            }
          } label: {
            Text(localized(app.behaviorMode.rawValue)).font(bodyFont)
              .padding(.vertical, 6 * uiScale).padding(.horizontal, 8 * uiScale)
          }
        }
        LabeledContent(localized("Animation")) {
          Menu {
            ForEach(MultiCodexPetsCore.AnimationState.allCases) { state in
              Button(localized(state.displayName)) { app.setAnimationState(state) }
            }
          } label: {
            Text(localized(app.settings.animationState.displayName)).font(bodyFont)
              .padding(.vertical, 6 * uiScale).padding(.horizontal, 8 * uiScale)
          }
          .disabled(app.behaviorMode != .manual)
        }
        Text(
          localized(
            "Choose Manual Animation to play a fixed animation. Session assignments are in Sessions."
          )
        )
        .font(bodyFont).foregroundStyle(.secondary)
      } header: {
        Text(localized("Animation Behavior")).font(headingFont)
      }
      Section {
        Text(localized("Choose the animation each session state plays for all pets."))
          .font(detailFont).foregroundStyle(.secondary)
        ForEach(AgentActivity.allCases, id: \.self) { activity in
          Picker(
            localized(activity.rawValue),
            selection: Binding(
              get: { app.settings.sessionAnimations.animation(for: activity) },
              set: { app.setSessionAnimation($0, for: activity) })
          ) {
            ForEach(MultiCodexPetsCore.AnimationState.allCases) { state in
              Text(localized(state.displayName)).tag(state)
            }
          }
          .font(detailFont)
        }
        Button(localized("Restore Default Animations"), action: app.resetSessionAnimations)
          .disabled(app.settings.sessionAnimations.overrides.isEmpty)
      } header: {
        Text(localized("Session Animations")).font(headingFont)
      }
      Section {
        VStack(alignment: .leading, spacing: 6 * uiScale) {
          Toggle(
            localized("V2 pets follow cursor"),
            isOn: Binding(
              get: { app.settings.followsCursor }, set: app.setFollowsCursor))
          Text(
            localized("V2 pets look toward the cursor while idle. Reduce Motion takes priority.")
          )
          .font(detailFont).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8 * uiScale)
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text(localized("Scale"))
            Spacer()
            Text(app.settings.scale.formatted(.percent.precision(.fractionLength(0))))
              .monospacedDigit().foregroundStyle(.secondary)
          }
          Slider(
            value: Binding(get: { app.settings.scale }, set: app.setScale),
            in: 0.5...2, step: 0.05
          ) {
            Text(localized("Scale"))
          }
          .labelsHidden()
          HStack {
            Text("50%").font(detailFont).foregroundStyle(.secondary)
            Spacer()
            ForEach(app.scaleOptions, id: \.value) { option in
              Button(option.title) { app.setScale(option.value) }
                .tint(abs(app.settings.scale - option.value) < 0.01 ? Color.accentColor : nil)
            }
            Spacer()
            Text("200%").font(detailFont).foregroundStyle(.secondary)
          }
          .buttonStyle(.bordered).controlSize(.large)
        }
        .padding(.vertical, 8)
      } header: {
        Text(localized("Pet Appearance")).font(headingFont)
      }
      Section {
        VStack(alignment: .leading, spacing: 6 * uiScale) {
          Toggle(
            localized("Session sound notifications"),
            isOn: Binding(
              get: { app.settings.sessionSoundNotifications }, set: app.setSessionSoundNotifications
            ))
          Text(
            localized(
              "Assigned visible pets notify when their session activity changes. Choose alert sounds in Pets."
            )
          )
          .font(detailFont).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8 * uiScale)
        if app.settings.sessionSoundNotifications {
          VStack(alignment: .leading, spacing: 12 * uiScale) {
            Text(localized("Notify for")).font(bodyFont.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180 * uiScale))], alignment: .leading) {
              ForEach(AgentActivity.allCases.filter { $0 != .unknown }, id: \.self) { activity in
                Toggle(
                  localized(activity.rawValue),
                  isOn: Binding(
                    get: { app.settings.notifiedActivities.contains(activity) },
                    set: { app.setNotifiedActivity(activity, enabled: $0) })
                ).toggleStyle(.checkbox).font(detailFont)
              }
            }
            Stepper(
              localizedFormat("Repeat quiet time: %d sec", Int(app.settings.notificationCooldown)),
              value: Binding(
                get: { app.settings.notificationCooldown }, set: app.setNotificationCooldown),
              in: 0...60)
          }.padding(.vertical, 8 * uiScale)
        }
      } header: {
        Text(localized("Session Alerts")).font(headingFont)
      }
    }
    .formStyle(.grouped)
  }

  private var sessions: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 5 * uiScale) {
          Text(localized("Agent Sessions")).font(.system(size: 22 * uiScale, weight: .semibold))
          Text(localizedFormat("%d conversations detected", app.detectedSessions.count))
            .font(detailFont).foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          app.refreshSessions()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help(localized("Refresh Sessions")).accessibilityLabel(localized("Refresh Sessions"))
      }
      Picker(
        localized("Assignment"),
        selection: Binding(
          get: { app.sessionRouting.mode }, set: app.setSessionMode)
      ) {
        Text(localized("Automatic")).tag(SessionRouting.Mode.automatic)
        Text(localized("One Session")).tag(SessionRouting.Mode.single)
        Text(localized("Per Pet")).tag(SessionRouting.Mode.perPet)
      }
      .pickerStyle(.segmented)

      if app.sessionRouting.mode == .perPet {
        HStack {
          Picker(
            localized("Assign to"),
            selection: Binding(
              get: { targetPetID ?? "" }, set: { assignmentPetID = $0 })
          ) {
            if app.selectedPetPackages.isEmpty { Text(localized("No pets selected")).tag("") }
            ForEach(app.selectedPetPackages, id: \.id) { Text(app.displayName(for: $0)).tag($0.id) }
          }
          Button(localized("Automatic")) { assign("automatic") }
          Button(localized("Idle")) { assign("idle") }
        }
        .disabled(targetPetID == nil)
      }

      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Label(assignmentSummary, systemImage: "link").font(detailFont).lineLimit(2)
            .help(
              localized(
                "Assignments are restored by conversation identity. Missing sessions remain Idle."))

        }
        Spacer()
        if app.behaviorMode != .sessions {
          Button(localized("Enable Session Mode")) { app.setBehaviorMode(.sessions) }
        }
      }
      HStack {
        TextField(localized("Search sessions"), text: $search)
          .textFieldStyle(.roundedBorder)
        Toggle(localizedFormat("Completed (%d)", completedCount), isOn: $showsCompleted)
          .toggleStyle(.checkbox).fixedSize()
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { agentFilters }.fixedSize(horizontal: true, vertical: false)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * uiScale), spacing: 8)], spacing: 8) {
          agentFilters
        }
      }
      .buttonStyle(.bordered).controlSize(.large)
      if app.sessionDetectionFailed {
        Label(
          localized("Session detection unavailable. Please try again."),
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.secondary)
      }
      sessionList
      Divider()
      HStack {
        if let checked = app.lastSessionCheck {
          Text(
            localizedFormat("Last checked: %@", checked.formatted(date: .omitted, time: .standard))
          )
          .font(detailFont).foregroundStyle(.secondary)
        }
        Spacer()
        if !app.sessionDiagnostics.isEmpty {
          Label(localized("Detection details"), systemImage: "exclamationmark.triangle")
            .font(detailFont).foregroundStyle(.secondary)
        }
      }
      if !app.sessionDiagnostics.isEmpty || !app.unlinkedProcesses.isEmpty {
        DisclosureGroup(localized("Detection details")) {
          ForEach(app.sessionDiagnostics, id: \.self) { Text(localized($0)).font(detailFont) }
          if let last = app.lastSuccessfulSessionCheck {
            Text(
              localizedFormat(
                "Last successful check: %@", last.formatted(date: .omitted, time: .standard))
            ).font(detailFont)
          }
          if !app.unlinkedProcesses.isEmpty {
            Text(
              localizedFormat(
                "%d processes without a linked conversation", app.unlinkedProcesses.count)
            ).font(detailFont)
            Text(localized("Background services and launchers are not assignable sessions."))
              .font(detailFont).foregroundStyle(.secondary)
            ForEach(app.unlinkedProcesses) { process in
              Text("\(process.agent.rawValue) · PID \(process.pid ?? 0)")
                .font(detailFont).foregroundStyle(.secondary)
            }
          }
        }.font(detailFont)
      }

    }
    .padding(8 * uiScale)
  }

  @ViewBuilder private var agentFilters: some View {
    serviceFilter(nil)
    ForEach([AgentSession.orca, .claude, .codex, .antigravity], id: \.self) { serviceFilter($0) }
  }

  private func serviceFilter(_ kind: AgentSession?) -> some View {
    let selected = agentFilter == kind
    let count = app.detectedSessions.filter {
      (kind == nil || $0.kind == kind) && (showsCompleted || $0.activity != .completed)
    }.count
    return Button {
      agentFilter = kind
    } label: {
      HStack(spacing: 6) {
        if let kind { brandIcon(kind, size: 22) }
        Text(kind?.rawValue ?? localized("All")).fixedSize(horizontal: true, vertical: false)
        Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
      }
      .font(detailFont.weight(selected ? .semibold : .regular))
      .padding(.horizontal, 10).padding(.vertical, 6)
      .frame(maxWidth: .infinity).contentShape(Rectangle())
      .background(
        selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }

  private var targetPetID: String? {
    app.selectedPetPackages.first { $0.id == assignmentPetID }?.id
      ?? app.selectedPetPackages.first?.id
  }

  private var assignedID: String? {
    app.sessionRouting.mode == .perPet
      ? targetPetID.flatMap { app.sessionRouting.sessionIDsByPet[$0] }
      : app.sessionRouting.mode == .single ? app.sessionRouting.singleSessionID : nil
  }

  private var assignmentSummary: String {
    if app.sessionRouting.mode == .automatic {
      return localized("Sessions are distributed automatically across agent types.")
    }
    if assignedID == "idle" { return localized("Assigned: Idle") }
    guard let assignedID else { return localized("Assigned: Automatic") }
    guard let session = app.detectedSessions.first(where: { $0.id == assignedID }) else {
      return localized("Assigned session unavailable — Idle")
    }
    return localizedFormat("Assigned: %@", session.title ?? localized("Untitled session"))
  }

  private var completedCount: Int {
    app.detectedSessions.filter { $0.activity == .completed }.count
  }

  private var filteredSessions: [DetectedAgentSession] {
    app.detectedSessions.filter { session in
      (agentFilter == nil || session.kind == agentFilter)
        && (showsCompleted || session.activity != .completed)
        && (search.isEmpty
          || [
            session.title ?? "", session.kind.rawValue,
            session.agent.rawValue, localized(session.activity.rawValue),
          ]
          .contains { $0.localizedStandardContains(search) })
    }
  }

  private var sessionList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if filteredSessions.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
            Text(
              localized(
                app.detectedSessions.isEmpty
                  ? "No agent sessions found. Start an agent to see it here."
                  : "No matching sessions. Try another search or show completed sessions.")
            )
            .multilineTextAlignment(.center).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity).padding(.vertical, 32)
        }
        ForEach([AgentSession.orca, .claude, .codex, .antigravity], id: \.self) { kind in
          let sessions = filteredSessions.filter { $0.kind == kind }
          if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 8) {
                brandIcon(kind, size: 30)
                Text(kind.rawValue).font(headingFont)
                Text("\(sessions.count)").font(bodyFont).foregroundStyle(.secondary)
                Spacer()
              }
              ForEach(AgentActivity.allCases, id: \.self) { activity in
                let matching = sessions.filter { $0.activity == activity }
                if !matching.isEmpty {
                  Label(localized(activity.rawValue), systemImage: statusSymbol(activity))
                    .font(detailFont).foregroundStyle(.secondary).padding(.leading, 4)
                  ForEach(matching) { session in sessionRow(session) }
                }
              }
            }
          }
        }
      }.padding(12 * uiScale)
    }
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
  }

  private func sessionRow(_ session: DetectedAgentSession) -> some View {
    Button {
      assign(session.id)
    } label: {
      HStack(spacing: 10) {
        if session.hostedByOrca { brandIcon(session.agent, size: 24) }
        VStack(alignment: .leading, spacing: 4) {
          Text(session.title ?? localized("Untitled session"))
            .font(bodyFont).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
          Text(
            session.pid.map { "\(session.agent.rawValue) · PID \($0)" }
              ?? localizedFormat("%@ · Orca conversation", session.agent.rawValue)
          )
          .font(detailFont).foregroundStyle(.secondary)
          if session.activity == .unknown, let raw = session.rawActivity, !raw.isEmpty {
            Text(localizedFormat("Unrecognized provider state: %@", raw))
              .font(detailFont).foregroundStyle(.secondary)
          }
        }
        if assignedID == session.id {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            .accessibilityLabel(localized("Assigned"))
        }
      }
      .padding(12 * uiScale).frame(minHeight: 64 * uiScale).contentShape(Rectangle())
      .background(
        assignedID == session.id ? Color.accentColor.opacity(0.12) : .clear,
        in: RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .disabled(app.sessionRouting.mode == .perPet && targetPetID == nil)
    .help(localizedFormat("Assign %@", session.title ?? localized("Untitled session")))
  }

  private func assign(_ id: String) {
    if app.sessionRouting.mode == .perPet {
      guard let petID = targetPetID else { return }
      app.selectSession(id, petID: petID)
    } else {
      app.selectSession(id)
    }
  }

  @ViewBuilder private func brandIcon(_ kind: AgentSession, size: CGFloat) -> some View {
    let size = size * uiScale
    if let image = AgentBrandImages.images[kind] {
      Image(nsImage: image).resizable()
        .renderingMode(image.isTemplate ? .template : .original)
        .interpolation(.high).scaledToFit().padding(size * 0.16)
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .background(
          Color.primary.opacity(0.06),
          in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
  }

  private func statusSymbol(_ activity: AgentActivity) -> String {
    switch activity {
    case .running: return "play.circle"
    case .monitoring: return "eye.circle"
    case .interrupted: return "stop.circle"
    case .unverified: return "questionmark.circle"
    case .approval: return "hand.raised"
    case .waiting: return "pause.circle"
    case .completed: return "checkmark.circle"
    case .failed: return "exclamationmark.circle"
    case .unknown: return "questionmark.circle"
    }
  }
}
