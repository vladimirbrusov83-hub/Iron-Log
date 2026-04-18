import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var loggingVM = LoggingViewModel()
    @State private var hasSeeded = false

    var body: some View {
        TabView {
            HomeView(loggingVM: loggingVM)
                .tabItem { Label("Log", systemImage: "flame.fill") }

            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }

            ProgramsView()
                .tabItem { Label("Programs", systemImage: "list.bullet.clipboard.fill") }

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.orange)
        .onAppear {
            guard !hasSeeded else { return }
            hasSeeded = true
            SeedData.seedExercises(context: modelContext)
            SeedData.seedPrograms(context: modelContext)
            _ = SeedData.ensureUser(context: modelContext)
        }
    }
}
