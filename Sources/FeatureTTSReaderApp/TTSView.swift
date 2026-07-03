import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var editingProfile: VoiceProfileTuning?
    @State private var showAddProfile = false
    @State private var showProfileExporter = false
    @State private var showProfileImporter = false
    @State private var profileExportData = Data()
    @State private var isTestingAudio = false
    @State private var audioTestResult: String?

    var body: some View {
        NavigationStack {
            List {
                serverSection
                voiceProfileSection
                templateSection
                tagSection
                statusSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("TTS")
            .sheet(isPresented: $showAddProfile) {
                VoiceFineTuneEditView(profile: nil) { p in
                    store.addVoiceProfile(p)
                }
                .environmentObject(store)
            }
            .sheet(item: $editingProfile) { profile in
                VoiceFineTuneEditView(profile: profile) { p in
                    store.updateVoiceProfile(p)
                }
                .environmentObject(store)
            }
            .fileExporter(isPresented: $showProfileExporter, document: JSONDocument(data: profileExportData),
                          contentType: .json, defaultFilename: "tts-voice-profiles") { result in
                switch result {
                case .success: store.statusMessage = "音色档案已导出"
                case .failure(let e): store.statusMessage = "导出失败: \(e.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showProfileImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { return }
                    if store.importVoiceProfiles(from: data) {
                        store.statusMessage = "音色档案已导入"
                    } else {
                        store.statusMessage = "导入失败: 格式错误"
                    }
                case .failure(let e):
                    store.statusMessage = "导入失败: \(e.localizedDescription)"
                }
            }
        }
    }

    // MARK: - TTS 服务器

    private var serverSection: some View {
        Section {
            if let server = store.activeServer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(serverStatusColor)
                            .frame(width: 8, height: 8)
                        Text(server.name).font(.headline)
                        Spacer()
                        if store.isTestingServer {
                            ProgressView().scaleEffect(0.7)
                        } else if !store.activeServerTestResult.isEmpty {
                            Text(store.activeServerTestResult)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Text(server.baseURL)
                        .font(.caption).foregroundColor(.secondary)
                }

                HStack {
                    Button("测试连接") { Task { await store.testActiveServer() } }
                        .disabled(store.isTestingServer)
                    Spacer()
                    Button("音频测试") {
                        Task {
                            isTestingAudio = true
                            audioTestResult = nil
                            let result = await store.testTTSSynthesize()
                            audioTestResult = result
                            isTestingAudio = false
                        }
                    }
                    .disabled(isTestingAudio || store.activeServer == nil)
                    Spacer()
                    NavigationLink("管理服务器") {
                        TTSServerListView().environmentObject(store)
                    }
                }
                .buttonStyle(.borderless)
                if let result = audioTestResult, !result.isEmpty {
                    Text(result).font(.caption).foregroundColor(.secondary)
                    if result.hasPrefix("合成成功"), let url = store.ttsTestAudioURL {
                        HStack(spacing: 16) {
                            Button("播放") {
                                do {
                                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                                    try AVAudioSession.sharedInstance().setActive(true)
                                } catch {}
                                if let player = try? AVAudioPlayer(contentsOf: url) {
                                    player.prepareToPlay()
                                    player.play()
                                }
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            Button("取消") {
                                audioTestResult = nil
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未配置 TTS 服务器").foregroundColor(.secondary)
                    Text("添加一台 TTS 服务器以开始使用朗读功能。")
                        .font(.caption).foregroundColor(.secondary)
                }
                NavigationLink("添加服务器") {
                    TTSServerListView().environmentObject(store)
                }
            }
        } header: {
            Label("TTS 服务器", systemImage: "server.rack")
        }
    }

    private var serverStatusColor: Color {
        let r = store.activeServerTestResult
        if r.isEmpty || r == "测试中..." { return .gray }
        if r.contains("ms") { return .green }
        return .red
    }

    // MARK: - 角色音色档案

    private var voiceProfileSection: some View {
        Section {
            if store.voiceProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("尚无角色别名").foregroundColor(.secondary)
                    Text("为常用角色创建别名并绑定音色和微调参数，朗读时将自动匹配。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(store.voiceProfiles) { profile in
                    Button(action: { editingProfile = profile }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile.alias.isEmpty ? profile.sourceVoiceID : profile.alias)
                                    .font(.headline)
                                Spacer()
                                if !profile.tags.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(Array(profile.tags.prefix(3)), id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                        if profile.tags.count > 3 {
                                            Text("+\(profile.tags.count - 3)")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            Text("音色: \(profile.sourceVoiceID)")
                                .font(.caption).foregroundColor(.secondary)
                            Text("语速\(profile.rateOffset) · 音调\(profile.pitchOffset) · 风格\(profile.style)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundColor(.primary)
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        store.removeVoiceProfile(store.voiceProfiles[i].id)
                    }
                }
            }

            Button(action: { showAddProfile = true }) {
                Label("创建角色别名", systemImage: "plus.circle")
            }

            if !store.voiceProfiles.isEmpty {
                HStack(spacing: 16) {
                    Button(action: exportVoiceProfiles) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    Button(action: { showProfileImporter = true }) {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Label("角色音色档案", systemImage: "person.and.waveform")
        }
    }

    private func exportVoiceProfiles() {
        guard let data = store.exportVoiceProfiles() else {
            store.statusMessage = "导出失败: 无数据"
            return
        }
        profileExportData = data
        showProfileExporter = true
    }

    // MARK: - 推荐模板

    private var templateSection: some View {
        Section {
            if store.roleTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("按小说类型预设角色阵容，朗读时自动推荐匹配的音色。")
                        .font(.subheadline).foregroundColor(.secondary)

                    templateCard(name: "男频小说",
                                 roles: ["旁白:沉稳男声 · 青年", "男主:阳光男声 · 元気", "女主:温柔女声", "反派:低沉 · 中年"])
                    templateCard(name: "历史穿越",
                                 roles: ["旁白:醇厚 · 叙事感", "穿越男主:沉稳 · 少年感", "谋士:沉稳 · 磁性", "将军:刚毅 · 中年"])
                    templateCard(name: "科幻未来",
                                 roles: ["旁白:冷静 · 专业", "主角:理性 · 青年", "AI/系统:机械 · 中性", "反派:冷峻"])
                    templateCard(name: "都市言情",
                                 roles: ["旁白:温婉 · 女声", "女主:甜美 · 少女", "男主:阳光 · 青年", "闺蜜:活泼 · 元気"])
                }
                .padding(.vertical, 4)
            } else {
                ForEach(store.roleTemplates.prefix(3)) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name).font(.subheadline).fontWeight(.semibold)
                        ForEach(template.roles.prefix(3)) { role in
                            let voiceName = store.voices.first(where: { $0.id == role.sourceVoiceID })?.name ?? role.sourceVoiceID
                            Text("  ·  \(role.title): \(voiceName)")
                                .font(.caption2).foregroundColor(.secondary)
                            if !role.voiceSuggestion.isEmpty {
                                Text("       \(role.voiceSuggestion)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        if template.roles.count > 3 {
                            Text("  ·  +\(template.roles.count - 3) 个角色")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            NavigationLink("管理模板 (\(store.roleTemplates.count))") {
                TemplateManageView().environmentObject(store)
            }
        } header: {
            Label("推荐模板", systemImage: "square.on.square")
        }
    }

    private func templateCard(name: String, roles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).fontWeight(.semibold)
            ForEach(roles, id: \.self) { role in
                Text("  ·  \(role)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - 标签预设

    private var tagSection: some View {
        Section {
            if store.tagPresets.isEmpty {
                Text("暂无标签预设")
                    .foregroundColor(.secondary)
            } else {
                ForEach(TagCategory.allCases) { category in
                    let tags = store.tagPresets.filter { $0.category == category }
                    if !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.displayName)
                                .font(.caption).fontWeight(.semibold)
                            HStack(spacing: 6) {
                                ForEach(tags) { tag in
                                    Text(tag.name)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            NavigationLink("管理标签") {
                TagManageView().environmentObject(store)
            }
        } header: {
            Label("标签预设", systemImage: "tag")
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section {
            Text(store.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TTSView_Previews: PreviewProvider {
    static var previews: some View {
        TTSView().environmentObject(ReaderStore())
    }
}
