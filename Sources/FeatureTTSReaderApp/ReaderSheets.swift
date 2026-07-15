import SwiftUI

// MARK: - ReaderSheets ViewModifier

struct ReaderSheets: ViewModifier {
    @Binding var showSettings: Bool
    @Binding var showFontPicker: Bool
    @Binding var showTOC: Bool
    @Binding var editingCharacter: CharacterProfile?
    @Binding var showAddCharacter: Bool
    @Binding var showAllRecommendations: Bool
    @Binding var showCharacterFromText: Bool
    @Binding var showCharacterList: Bool
    let selectedTextForCharacter: String
    let bookID: UUID
    let currentChapterID: UUID
    let currentChapterIndex: Int
    let chaptersList: [BookChapter]
    let onTOCSelect: (Int) -> Void
    let onCharacterEdit: (CharacterProfile) -> Void
    let store: ReaderStore
    @Binding var aiCacheAvailable: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSettings) {
                ReaderSettingsView().environmentObject(store).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFontPicker) {
                FontPickerView().environmentObject(store).presentationDetents([.medium])
            }
            .sheet(isPresented: $showTOC) {
                ChapterListView(currentChapterID: currentChapterID, chapters: chaptersList) { chapter, index in
                    ReaderStore.debugLog("[TOC] idx=\(index)")
                    onTOCSelect(index)
                }
                .environmentObject(store)
                .presentationDetents([.large])
            }
            .sheet(item: $editingCharacter) { character in
                CharacterEditorView(
                    character: character
                ) { updated in
                    onCharacterEdit(updated)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showAddCharacter) {
                AddCharacterView { name, genderStr, age, tone in
                    let gender: CharacterGender = genderStr == "男性" ? .male : (genderStr == "女性" ? .female : .unknown)
                    store.addCharacter(name: name, gender: gender, age: age, tone: tone, bookID: bookID)
                    showAddCharacter = false
                }
            }
            .sheet(isPresented: $showAllRecommendations) {
                AllRecommendationsView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCharacterFromText) {
                QuickCharacterAddView(
                    candidateName: selectedTextForCharacter,
                    bookText: store.bookText,
                    existingCharacters: store.characters,
                    onAdd: { name, genderStr, age, tone in
                        let gender: CharacterGender = genderStr == "男性" ? .male : (genderStr == "女性" ? .female : .unknown)
                        store.addCharacter(name: name, gender: gender, age: age, tone: tone, bookID: bookID)
                    },
                    onEdit: { character in
                        editingCharacter = character
                    }
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showCharacterList) {
                CharacterListView(
                    bookID: bookID,
                    characters: Binding(
                        get: { store.characters },
                        set: { store.characters = $0 }
                    ),
                    availableVoices: store.voices.map { v in
                        EdgeVoiceInfo(
                            id: v.id,
                            name: v.name,
                            gender: v.gender.rawValue,
                            locale: v.locale,
                            styles: v.styleList
                        )
                    },
                    onDismiss: { showCharacterList = false },
                    resynthesizingSpeaker: Binding(
                        get: { store.resynthesizingSpeaker },
                        set: { store.resynthesizingSpeaker = $0 }
                    ),
                    aiCacheAvailable: $aiCacheAvailable
                ).environmentObject(store)
            }
    }
}

// MARK: - AllRecommendationsView

struct AllRecommendationsView: View {
    @EnvironmentObject private var store: ReaderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.recommendations) { rec in
                    Section(header: Text("\(rec.profile.name)（出现 \(rec.count) 次）")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(rec.suggestedVoices) { voice in
                                    VStack(spacing: 2) {
                                        Text(voice.name).font(.caption).fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.1)).cornerRadius(10)
                                    .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("全部推荐")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

// MARK: - PageMode

enum PageMode: String, CaseIterable, Identifiable {
    case scroll = "scroll"
    case horizontal = "horizontal"
    case vertical = "vertical"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .scroll: return "滚动"
        case .horizontal: return "左右翻页"
        case .vertical: return "上下翻页"
        }
    }
    var icon: String {
        switch self {
        case .scroll: return "scroll"
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        }
    }
}
