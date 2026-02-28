import SwiftUI

struct ContentView: View {
    private enum RootScreen {
        case menu
        case director
        case catSeedream
    }

    @State private var screen: RootScreen = .menu

    var body: some View {
        Group {
            if screen == .director {
                DirectorView(onExit: {
                    screen = .menu
                })
            } else if screen == .catSeedream {
                CatNanoBananaTestView(onClose: {
                    screen = .menu
                })
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("Storyworld")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)

                        Button("ENTER DIRECTOR") {
                            screen = .director
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(.black)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white)
                        )
                    }

                    VStack {
                        Spacer()
                        Button("IMAGE TEST") {
                            screen = .catSeedream
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.14))
                        )
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
