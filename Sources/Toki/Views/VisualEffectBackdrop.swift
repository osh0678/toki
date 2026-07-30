import AppKit
import SwiftUI

/// Behind-window blur that gives the panel its body.
///
/// `glassEffect` alone on a fully transparent borderless window reads as washed out —
/// one translucent layer over the desktop has little density, so text loses contrast.
/// This AppKit material sits underneath to supply that density while still blurring
/// the desktop; the glass layers on the cards above supply the refraction.
///
/// How much density is purely a matter of taste and of what wallpaper sits behind it,
/// so the caller fades this view with `panelOpacity`: at 0 the panel is bare glass, at
/// 1 it is a fully opaque HUD material.
struct VisualEffectBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // The darkest material available, so the opacity knob has the widest range.
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.layer?.cornerRadius = cornerRadius
    }
}
