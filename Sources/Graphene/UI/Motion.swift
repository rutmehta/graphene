import SwiftUI

/// The shell's motion table (arc-look.md §4). Every animated surface reads its
/// curve from here, and `reduced(_:)` swaps any spring or slide for the
/// opacity-only fade that Reduce Motion asks for.
enum Motion: CaseIterable {
    /// Sidebar collapse and expand; the page card follows.
    case collapse
    /// The collapsed sidebar peeking over the page card.
    case peek
    /// Space switch: the rows slide horizontally.
    case spaceSwitch
    /// Space switch: the chrome gradient cross-fades.
    case gradient
    /// Row hover and selection.
    case hover
    /// Command bar presentation.
    case commandIn
    /// Command bar dismissal.
    case commandOut
    /// Chat panel and Little Arc.
    case panel
    /// Toast arrival and departure.
    case toast
    /// Progress bar width tracking `estimatedProgress`.
    case progress
    /// Progress bar fade-out at completion.
    case progressFade

    enum Curve: Equatable {
        case easeOut(duration: Double)
        case spring(response: Double, dampingFraction: Double)
    }

    var curve: Curve {
        switch self {
        case .collapse: return .spring(response: 0.30, dampingFraction: 0.75)
        case .peek: return .spring(response: 0.28, dampingFraction: 0.8)
        case .spaceSwitch: return .easeOut(duration: 0.18)
        case .gradient: return .easeOut(duration: 0.24)
        case .hover: return .easeOut(duration: 0.10)
        case .commandIn: return .easeOut(duration: 0.12)
        case .commandOut: return .easeOut(duration: 0.09)
        case .panel: return .spring(response: 0.32, dampingFraction: 0.8)
        case .toast: return .easeOut(duration: 0.16)
        case .progress: return .easeOut(duration: 0.15)
        case .progressFade: return .easeOut(duration: 0.20)
        }
    }

    /// The curve Reduce Motion substitutes for every spring and slide.
    static let reducedCurve = Curve.easeOut(duration: 0.12)

    var animation: Animation { Self.animation(curve) }

    /// This motion, or the opacity-only fade when Reduce Motion is on.
    func reduced(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? Self.animation(Self.reducedCurve) : animation
    }

    private static func animation(_ curve: Curve) -> Animation {
        switch curve {
        case .easeOut(let duration): return .easeOut(duration: duration)
        case .spring(let response, let damping): return .spring(response: response, dampingFraction: damping)
        }
    }

    // MARK: distances

    /// Command bar scale at the start of presentation.
    static let commandScale: CGFloat = 0.98
    /// Little Arc window scale at the start of presentation.
    static let littleArcScale: CGFloat = 0.96
    /// Chat panel horizontal travel.
    static let panelOffset: CGFloat = 24
    /// Space switch horizontal travel.
    static let spaceSlide: CGFloat = 24
    /// Toast vertical travel.
    static let toastRise: CGFloat = 8

    // MARK: transitions

    /// Command bar: fade plus a slight scale about its fixed top edge; a plain fade under Reduce Motion.
    static func commandBar(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .scale(scale: commandScale, anchor: .top))
    }

    /// Chat panel: slides in from the trailing edge with a fade.
    static func panel(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .offset(x: panelOffset).combined(with: .opacity)
    }

    /// Toast: rises from below with a fade.
    static func toast(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .offset(y: toastRise).combined(with: .opacity)
    }
}
