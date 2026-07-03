# Character Assignment Skill

Used when adding character assignment and template application features to views like BookDetailView.

## Available Components

### CharacterAssignmentPanel
A reusable view that provides:
- **Scan whole book** button with estimated time and progress bar
- **System template picker** for applying pre-made role templates
- **Character role list** showing narrator + characters with current voice config
- **Fine-tune** button per character (opens CharacterEditorView)
- **Export/Import** book character config as JSON

### Integration Pattern

1. Add `CharacterAssignmentPanel` as a section in the target view
2. Provide the book's text for scanning
3. The panel manages its own loading/template/editing state

## Store Methods Used

- `scanCharacters(chapterText:)` — async, infers characters from text
- `applyTemplate(_:)` — applies a RoleTemplate to global characters
- `deleteCharacter(at:)`, `addCharacter(...)` — character CRUD
- `applyVoice(_:toCharacterID:)` — assign voice to character
- `exportVoiceProfiles()` / `importVoiceProfiles(from:)` — book-level config
