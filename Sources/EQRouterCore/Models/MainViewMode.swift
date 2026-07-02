import Foundation

/// Top-level UI mode — toggled from the chip in the top bar. The EQ
/// view holds the routing + EQ editor (the audio path); the community
/// view holds curated text articles + an Import EQ flow for community
/// submissions. Persisted across launches.
public enum MainViewMode: String, Codable, CaseIterable {
    case eq
    case community

    public var displayLabel: String {
        switch self {
        case .eq:        return "EQ"
        case .community: return "COMMUNITY"
        }
    }

    public var systemIcon: String {
        switch self {
        case .eq:        return "slider.horizontal.3"
        case .community: return "person.2.fill"
        }
    }

    public var other: MainViewMode {
        switch self {
        case .eq:        return .community
        case .community: return .eq
        }
    }
}

/// Plain-text article shown in the community section. Renderer is
/// markdown-aware (SwiftUI's `Text` already handles inline `**`/`*`).
public struct CommunityArticle: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var summary: String
    public var body: String
    public var author: String?
    public var topic: String

    public init(
        id: String, title: String, summary: String,
        body: String, author: String? = nil, topic: String
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.author = author
        self.topic = topic
    }
}

/// Curated starter set of articles. Future versions can fetch from a
/// remote feed; for now these are bundled — they're the kind of
/// "community recommendations" the section is for.
public enum CommunityContent {
    public static let articles: [CommunityArticle] = [
        CommunityArticle(
            id: "intro.import-format",
            title: "What EQ files can I import?",
            summary: "The Import button accepts the de-facto standard format used by AutoEq and EqualizerAPO — line-by-line parametric filters.",
            body: """
            Imported files follow this shape (one line per filter, plus a single Preamp line at the top):

            Preamp: -6.7 dB
            Filter 1: ON LSC Fc 105 Hz Gain 12.2 dB Q 0.70
            Filter 2: ON PK Fc 61 Hz Gain -10.1 dB Q 0.34
            ...

            Filter type tokens: PK (peaking), LS / LSC (low shelf), HS / HSC (high shelf). Unknown tokens and comment lines are silently skipped.

            This is the same syntax AutoEq writes to ParametricEQ.txt and the same one EqualizerAPO accepts in its config. If your file looks like the example above, it'll import.

            Imported files become Saved presets — not headphone correction profiles. The correction slot stays reserved for vetted, credible measurements from the bundled AutoEq correction library, while community imports stay editable and separate.
            """,
            author: nil,
            topic: "Import"
        ),
        CommunityArticle(
            id: "rec.headphone-eq-workflow",
            title: "The canonical headphone-EQ workflow",
            summary: "Apply a correction profile underneath. Add broad, low-Q tonal shaping on top. Don't try to make the user EQ surgical.",
            body: """
            The pattern Audio Hijack, AutoEq, Wavelet, and EqualizerAPO + Peace all converge on:

            1. Correction profile (surgical Qs, fixed) sits at the bottom of the chain. It fixes specific resonances and dips in your specific headphone.

            2. User EQ (broad, musical Qs) sits above it. Q ≈ 0.7 – 1.4 is the sweet spot. Anything narrower at the same frequency as a surgical correction filter will compound with it and you'll hear the correction effect twice.

            EQK keeps these layers independent on purpose. The 10-band custom EQ uses octave-clean Q (≈ √2) by default. Genre presets nudge that toward genre-typical character. Loading a correction profile does not re-shape your custom Qs.

            If you're importing community files: they go into Saved. The original AutoEq surgical-Q character is preserved by the userParametricEQ stage — your slider sees the file's intent, not an approximation.
            """,
            author: nil,
            topic: "Recommendation"
        ),
        CommunityArticle(
            id: "rec.why-q-1.4-default",
            title: "Why the default Q is √2 (~1.414), not 1.0",
            summary: "Octave-spaced bands at Q = 1.0 have overlapping skirts. Q = √2 makes each band cleanly own its octave.",
            body: """
            Each EQK band sits one octave apart from its neighbours (31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz).

            With Q = 1.0, the −3 dB points of adjacent bands meet at half-octave — and beyond that, the skirts overlap significantly. Boost two adjacent bands together and you get extra build-up in the seam.

            With Q = √2 (≈ 1.4142), each band's −3 dB skirts sit exactly at half-octave from its centre — meeting the next band's edge cleanly, without overlap. Adjacent boosts don't double-count.

            This is the value EQK ships as Flat. If you want broader / Butterworth-feeling shaping, the Reference and Classical genres run at Q ≈ 0.7 across all bands.
            """,
            author: nil,
            topic: "Recommendation"
        ),
        CommunityArticle(
            id: "rec.browser-eq-honestly",
            title: "Why browsers aren't in the route picker",
            summary: "All Safari tabs share one media process. No per-tab audio isolation exists on macOS.",
            body: """
            CoreAudio process taps capture audio from a single PID. Safari's audio doesn't come from `com.apple.Safari` — it comes from `com.apple.WebKit.GPU`, the single media-rendering process that handles every tab.

            That means the best a tap could do for a browser is grab the mixed sum of every tab's audio simultaneously. There's no API on macOS to separate per-tab audio streams. This isn't a limitation EQK can work around in userspace.

            On top of that, WebKit.GPU can renegotiate its output sample rate mid-stream when tabs open/close (44.1 kHz ↔ 48 kHz are both common), which would leave the EQ filtering at the wrong frequencies until you stop and restart the route.

            For now: browsers are out of the picker. Dedicated music / video apps (Music, Spotify, Apple TV, Plex, Netflix, etc.) work cleanly because each one has its own audio path.
            """,
            author: nil,
            topic: "Recommendation"
        ),
    ]
}
