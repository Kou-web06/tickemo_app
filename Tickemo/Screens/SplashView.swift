import SwiftUI

struct SplashView: View {
    var body: some View {
        Image("splash")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}
