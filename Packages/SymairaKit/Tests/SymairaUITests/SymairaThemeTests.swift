import AppKit
import SwiftUI
import Testing
import SymairaTheme

// MARK: - Color(hex:) parsing

/// The hex parser is the foundation of every palette token, so its edge
/// cases get locked down first. Colors are verified through resolved RGBA
/// components (color math only — no rendering, no NSApplication).
@Suite struct ColorHexParsingTests {
    @Test func sixDigitHexWithoutHash() {
        #expect(ColorHexParsingTests.rgba(Color(hex: "E5C397")) == ColorHexParsingTests.close(0xE5, 0xC3, 0x97))
    }

    @Test func sixDigitHexWithHash() {
        #expect(ColorHexParsingTests.rgba(Color(hex: "#0D0C0A")) == ColorHexParsingTests.close(0x0D, 0x0C, 0x0A))
    }

    @Test func threeDigitHexExpandsEachChannel() {
        // "ABC" → AA BB CC in 12-bit: 0xA*17, 0xB*17, 0xC*17.
        #expect(ColorHexParsingTests.rgba(Color(hex: "ABC")) == ColorHexParsingTests.close(170, 187, 204))
    }

    @Test func eightDigitHexParsesARGB() {
        // "80FFFFFF" = alpha 0x80 (≈0.502), white RGB.
        let c = ColorHexParsingTests.rgba(Color(hex: "80FFFFFF"))
        #expect(c.a == ColorHexParsingTests.close(0x80))
        #expect(c.r == 1)
        #expect(c.g == 1)
        #expect(c.b == 1)
    }

    @Test func leadingZerosArePreserved() {
        // "0F0F0F" must not collapse leading zero nibbles.
        #expect(ColorHexParsingTests.rgba(Color(hex: "0F0F0F")) == ColorHexParsingTests.close(0x0F, 0x0F, 0x0F))
    }

    @Test func invalidHexFallsBackToOpaqueBlack() {
        #expect(ColorHexParsingTests.rgba(Color(hex: "zzz")) == ColorHexParsingTests.close(0, 0, 0))
    }

    @Test func emptyHexFallsBackToOpaqueBlack() {
        #expect(ColorHexParsingTests.rgba(Color(hex: "")) == ColorHexParsingTests.close(0, 0, 0))
    }

    // MARK: - Helpers

    typealias RGBA = (r: Double, g: Double, b: Double, a: Double)

    static func rgba(_ color: Color) -> RGBA {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        return (
            (ns.redComponent * 1000).rounded() / 1000,
            (ns.greenComponent * 1000).rounded() / 1000,
            (ns.blueComponent * 1000).rounded() / 1000,
            (ns.alphaComponent * 1000).rounded() / 1000
        )
    }

    static func close(_ byte: UInt64) -> Double {
        (Double(byte) / 255 * 1000).rounded() / 1000
    }

    static func close(_ r: UInt64, _ g: UInt64, _ b: UInt64) -> RGBA {
        (close(r), close(g), close(b), 1)
    }
}

// MARK: - Adaptive theme resolution

@Suite struct AdaptiveThemeTests {
    @Test func darkBackgroundMatchesStaticToken() {
        #expect(rgba(SymairaTheme.backgroundPrimary(for: .dark)) == rgba(SymairaTheme.bgDark))
        #expect(rgba(SymairaTheme.backgroundSecondary(for: .dark)) == rgba(SymairaTheme.bgDarker))
        #expect(rgba(SymairaTheme.foregroundPrimary(for: .dark)) == rgba(SymairaTheme.textPrimary))
        #expect(rgba(SymairaTheme.foregroundSecondary(for: .dark)) == rgba(SymairaTheme.textSecondary))
        #expect(rgba(SymairaTheme.foregroundMuted(for: .dark)) == rgba(SymairaTheme.textMuted))
    }

    @Test func lightBackgroundUsesWarmPaper() {
        #expect(rgba(SymairaTheme.backgroundPrimary(for: .light)) == ColorHexParsingTests.close(0xF7, 0xF3, 0xEC))
        #expect(rgba(SymairaTheme.backgroundSecondary(for: .light)) == ColorHexParsingTests.close(0xEE, 0xE7, 0xDC))
        #expect(rgba(SymairaTheme.surfaceOpaque(for: .light)) == ColorHexParsingTests.close(0xFF, 0xFC, 0xF7))
    }

    @Test func lightForegroundIsWarmDarkInk() {
        #expect(rgba(SymairaTheme.foregroundPrimary(for: .light)) == ColorHexParsingTests.close(0x21, 0x1D, 0x17))
        #expect(rgba(SymairaTheme.foregroundSecondary(for: .light)) == ColorHexParsingTests.close(0x5F, 0x58, 0x4F))
        #expect(rgba(SymairaTheme.foregroundMuted(for: .light)) == ColorHexParsingTests.close(0x75, 0x6D, 0x63))
    }

    @Test func darkAndLightResolveDifferently() {
        #expect(rgba(SymairaTheme.backgroundPrimary(for: .dark)) != rgba(SymairaTheme.backgroundPrimary(for: .light)))
        #expect(rgba(SymairaTheme.foregroundPrimary(for: .dark)) != rgba(SymairaTheme.foregroundPrimary(for: .light)))
    }

    @Test func cardBackgroundCarriesGlassOpacity() {
        // bgCard is bgColor-ish at 65% opacity — the glass effect is a token
        // invariant that must not silently become fully opaque.
        #expect(rgba(SymairaTheme.bgCard).a == 0.65)
    }

    // MARK: - Helpers

    private func rgba(_ color: Color) -> ColorHexParsingTests.RGBA {
        ColorHexParsingTests.rgba(color)
    }
}

// MARK: - Design-token constants

@Suite struct DesignTokenConstantsTests {
    @Test func spacingScaleIsCanonical() {
        #expect(SymairaSpacing.xSmall == 4)
        #expect(SymairaSpacing.small == 8)
        #expect(SymairaSpacing.medium == 12)
        #expect(SymairaSpacing.large == 16)
        #expect(SymairaSpacing.xLarge == 24)
        #expect(SymairaSpacing.section == 32)
        #expect(SymairaSpacing.spacious == 48)
    }

    @Test func radiusScaleIsCanonical() {
        #expect(SymairaRadius.control == 10)
        #expect(SymairaRadius.card == 16)
        #expect(SymairaRadius.panel == 20)
    }

    @Test func metricsAreCanonical() {
        #if os(iOS)
        #expect(SymairaMetrics.minimumControlHeight == 44)
        #else
        #expect(SymairaMetrics.minimumControlHeight == 34)
        #endif
        #expect(SymairaMetrics.readableContentWidth == 760)
        #expect(SymairaMetrics.glassGroupSpacing == 12)
        #expect(SymairaMetrics.emptyStateSymbolSize == 36)
    }

    @Test func textRoleTrackingOnlyOnSectionLabels() {
        #expect(SymairaTextRole.sectionLabel.tracking == 0.6)
        for role in [SymairaTextRole.display, .title, .heading, .subheading, .body,
                     .bodyEmphasized, .callout, .secondary, .caption, .mono, .monoSmall] {
            #expect(role.tracking == 0, "role \(role) must not carry tracking")
        }
    }

    @Test func textRoleForegroundFollowsContrastTier() {
        // Primary-tier roles resolve to the primary foreground in dark mode.
        for role in [SymairaTextRole.display, .title, .heading, .subheading, .body,
                     .bodyEmphasized, .callout, .mono] {
            #expect(
                ColorHexParsingTests.rgba(role.foreground(for: .dark))
                    == ColorHexParsingTests.rgba(SymairaTheme.textPrimary),
                "role \(role) should use the primary foreground"
            )
        }
        // Muted-tier roles must never resolve to the primary ink.
        for role in [SymairaTextRole.caption, .sectionLabel, .secondary, .monoSmall] {
            #expect(
                ColorHexParsingTests.rgba(role.foreground(for: .dark))
                    != ColorHexParsingTests.rgba(SymairaTheme.textPrimary),
                "role \(role) must stay in its muted tier"
            )
        }
    }
}
