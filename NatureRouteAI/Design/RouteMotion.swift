import SwiftUI

enum RouteMotion {
    static let quick = Animation.easeOut(duration: 0.16)
    static let selection = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let reveal = Animation.easeInOut(duration: 0.24)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }
}
