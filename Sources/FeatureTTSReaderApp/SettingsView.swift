import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ReaderStore
    @State private var testResult: String = ""

    var body: some View {
        Form {
            Section(header: Text("TTS 服务")) {
                TextField("TTS 服务地址", text: $store.apiEndpoint)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("可选 API Key", text: $store.apiKey)
                Button("测试连接") {
                    Task {
                        testResult = "测试中..."
                        testResult = await store.testTTSConnection()
                    }
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).foregroundColor(.secondary)
                }
            }

            Section(header: Text("阅读器设置")) {
                HStack {
                    Text("字号")
                    Slider(value: $store.readerFontSize, in: 14...32, step: 1)
                    Text("\(Int(store.readerFontSize))")
                }
                HStack {
                    Text("行距")
                    Slider(value: $store.readerLineSpacing, in: 0...20, step: 1)
                    Text("\(Int(store.readerLineSpacing))")
                }
                Picker("主题", selection: $store.readerTheme) {
                    ForEach(ReaderTheme.allCases, id: \ .self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section {
                Button("保存设置") {
                    store.saveSettings()
                    store.saveState()
                }
            }
        }
        .navigationTitle("设置")
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(ReaderStore())
    }
}
