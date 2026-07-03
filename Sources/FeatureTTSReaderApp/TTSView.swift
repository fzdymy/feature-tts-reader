import SwiftUI

struct TTSView: View {
    @EnvironmentObject private var store: ReaderStore
    var body: some View {
        Text("TTS")
    }
}

struct TTSView_Previews: PreviewProvider {
    static var previews: some View {
        TTSView().environmentObject(ReaderStore())
    }
}
