import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SandGardenView()
                .tabItem {
                    Label("Sand", systemImage: "circle.grid.3x3.fill")
                }
            MagneticSlimeView()
                .tabItem {
                    Label("Slime", systemImage: "drop.fill")
                }
            CardFlickView()
                .tabItem {
                    Label("Cards", systemImage: "rectangle.stack.fill")
                }
        }
        .tint(.white)
    }
}
