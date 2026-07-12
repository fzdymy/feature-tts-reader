import re

with open('Sources/FeatureTTSReaderApp/TTSView.swift', 'r') as f:
    content = f.read()

# 1. Remove duplicate functions (keep first occurrence)
funcs_to_dedup = [
    'loadWorkerConfigs',
    'saveWorkerConfigs',
    'getSelectedWorkerConfig',
    'buildCustomTTSConfig',
    'buildSegmentsPreview',
    'buildSimpleSpeakerMap',
    'buildSpeakerMap',
]

for func_name in funcs_to_dedup:
    pattern = r'(private func ' + re.escape(func_name) + r'\(.*?\)(?:\s*async)?\s*(?:->\s*[^{]+)?\s*\{)'
    matches = list(re.finditer(pattern, content))
    if len(matches) > 1:
        # Keep first, remove others
        for match in reversed(matches[1:]):  # Remove from last to first to preserve positions
            start = match.start()
            # Find end of function
            brace_count = 0
            in_string = False
            escape = False
            func_end = -1
            for i in range(match.start(), len(content)):
                ch = content[i]
                if escape:
                    escape = False
                    continue
                if ch == '\\':
                    escape = True
                    continue
                if ch == '"' and not escape:
                    in_string = not in_string
                    continue
                if in_string:
                    continue
                if ch == '{':
                    brace_count += 1
                elif ch == '}':
                    brace_count -= 1
                    if brace_count == 0:
                        func_end = i + 1
                        break
            if func_end != -1:
                content = content[:match.start()] + content[func_end:]
                print(f"Removed duplicate {func_name}")

# 2. Move WorkerEditView outside TTSView struct
worker_start = content.find('private struct WorkerEditView: View {')
if worker_start != -1:
    # Find end of WorkerEditView
    brace_count = 0
    in_string = False
    escape = False
    worker_end = -1
    for i in range(worker_start, len(content)):
        ch = content[i]
        if escape:
            escape = False
            continue
        if ch == '\\':
            escape = True
            continue
        if ch == '"' and not escape:
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == '{':
            brace_count += 1
        elif ch == '}':
            brace_count -= 1
            if brace_count == 0:
                worker_end = i + 1
                break
    if worker_end != -1:
        worker_struct = content[worker_start:worker_end]
        worker_struct = worker_struct.replace('private struct WorkerEditView:', 'struct WorkerEditView:', 1)
        # Remove from inside TTSView
        content = content[:worker_start] + content[worker_end:]
        # Insert before 'private extension CharacterSet'
        tts_end = content.find('private extension CharacterSet')
        if tts_end != -1:
            content = content[:worker_end] + '\n\n// MARK: - Worker Edit Sheet\n\n' + worker_struct + '\n\n' + content[worker_end:]
        else:
            content += '\n\n// MARK: - Worker Edit Sheet\n\n' + worker_struct

# 2. Remove 'private ' from functions inside TTSView struct body
body_start = content.find('var body: some View {')
if body_start != -1:
    # Find end of TTSView struct
    brace_count = 0
    in_string = False
    escape = False
    body_end = -1
    for i in range(body_start, len(content)):
        ch = content[i]
        if escape:
            escape = False
            continue
        if ch == '\\':
            escape = True
            continue
        if ch == '"' and not escape:
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == '{':
            brace_count += 1
        elif ch == '}':
            brace_count -= 1
            if brace_count == 0:
                body_end = i + 1
                break
    if body_end != -1:
        body_section = content[body_start:body_end]
        # Remove 'private ' from functions in body
        body_section = re.sub(r'^    private func ', '    func ', body_section, flags=re.MULTILINE)
        content = content[:body_start] + body_section + content[body_end:]

# Fix WorkerEditView - remove 'private ' prefix
content = re.sub(r'private struct WorkerEditView:', 'struct WorkerEditView:', content)

# Fix TTSConfigInfo and SegmentPreview - make them fileprivate
content = re.sub(r'private struct TTSConfigInfo', 'fileprivate struct TTSConfigInfo', content)
content = re.sub(r'private struct SegmentPreview', 'fileprivate struct SegmentPreview', content)

# Fix buildCustomTTSConfig, buildSegmentsPreview, buildSimpleSpeakerMap, buildSpeakerMap, buildSegmentsPreview - make them fileprivate
for fname in ['buildCustomTTSConfig', 'buildSegmentsPreview', 'buildSimpleSpeakerMap', 'buildSpeakerMap', 'buildSegmentsPreview']:
    content = content.replace(f'private func {fname}(', f'fileprivate func {fname}(')

# Fix WorkerEditView - remove 'private ' prefix
content = content.replace('private struct WorkerEditView:', 'struct WorkerEditView:')

# Fix private func in TTSView struct body - remove 'private ' prefix
body_start = content.find('var body: some View {')
if body_start != -1:
    # Find end of TTSView struct (matching brace)
    brace_count = 0
    in_string = False
    escape = False
    struct_end = -1
    for i in range(content.find('struct TTSView: View {'), len(content)):
        ch = content[i]
        if ch == '\\':
            escape = not escape
            continue
        if ch == '"' and not escape:
            in_string = not in_string
            continue
        if ch == '{' and not in_string:
            brace_count += 1
        elif ch == '}' and not in_string:
            brace_count -= 1
            if brace_count == 0:
                struct_end = i + 1
                break
    if struct_end != -1:
        # Remove 'private ' from functions in struct body
        struct_section = content[content.find('struct TTSView: View {'):struct_end]
        struct_section = re.sub(r'^    private func ', '    func ', struct_section, flags=re.MULTILINE)
        content = content[:content.find('struct TTSView: View {')] + struct_section + content[struct_end:]

# Save
with open('Sources/FeatureTTSReaderApp/TTSView.swift', 'w') as f:
    f.write(content)

print("Done fixing TTSView.swift")