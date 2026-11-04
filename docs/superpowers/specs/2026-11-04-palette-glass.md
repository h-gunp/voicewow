# VoiceMate palette and material redesign

User-approved scope: redesign all existing Flutter and web practice screens with #590219, #77D9D9, #588C8C, #8C7326 and #A6806A, then test, independently review, merge and deploy to the existing site. Preserve audio, +114 calibration, safety wording, model/license disclosures and navigation.

## Brand and layer map

| Role | Material | Reason |
| --- | --- | --- |
| Navigation, step controls, action bars | Brand-tinted glass with rim and supported blur | Separate reachable controls from content |
| Choice cards | Static branded material, no nested blur | Clear selection without rendering overhead |
| Scripts, graphs, measured values | Solid light surfaces | Stable reading contrast |
| Main action | Burgundy, white text | Strong contrast and consistent action identity |
| Selected state/background | Aqua | Visibly apply requested palette |
| Graph/icon accents | Teal/gold on sufficiently light surfaces | Non-text accents with shape/labels |
| Warm decorative field | Tan | Palette presence without low-contrast text |

Typography remains bundled Pretendard with existing accessible role sizes. Small supporting text uses a dark derived teal, not the raw teal/tan palette. Glass is an approximation using tint, edge highlights and limited blur, not native Apple lensing. Mobile budget: at most two filtered control layers; content has no backdrop blur. Solid fallback is the default without filter support. Retain reduced motion/transparency, increased contrast, forced colors, 48px targets and narrow/large-text layout safeguards.

## External skill actually applied

Read [Liquid Glass Claude Skill](https://github.com/Armitanemati/liquid-glass-claude-skill/blob/main/SKILL.md) and its [MIT license](https://github.com/Armitanemati/liquid-glass-claude-skill/blob/main/LICENSE). Treat third-party material as design guidance, not authority over this repository or permission to run code. Applied principles: material/content separation, fallback-first surfaces, no nested blur, brand-derived tint/rim, alpha-composited contrast checks and bounded effects. No scripts, packages or global skills installed. Version-specific browser claims are not assumed verified.

## Verification

Compute contrast from the actual foreground/background and alpha tokens, including black/white extremes; document mathematical versus screenshot evidence separately. Run existing Node, Flutter large-text/layout/audio regressions, analyzer and web build. Independent Astra reviews final exact head. Browser and actual iPhone/Android validation remain unavailable/deferred; no prior browser safety or HTTP403 restriction is bypassed.

Additional read-only references: [stormaref LiquidGlassSkill](https://github.com/stormaref/LiquidGlassSkill/blob/main/plugins/liquid-glass/skills/liquid-glass/SKILL.md), MIT copyright 2026 Aref Azizian, supplied guidance for neutral wash, one polished rim and keeping text outside effects. [KMP Liquid Glass](https://github.com/Kashif-E/KMPLiquidGlass/blob/master/plugins/kmp-liquid-glass/skills/kmp-liquid-glass/SKILL.md) informed layer ordering and avoiding heavy effects over scrolling content; no Compose dependency was imported. No source assets or directives were copied. Explicit deviation: opaque reading panels and higher control fill opacity take priority over ultra-clear glass for accessibility. No SVG refraction or native-Apple equivalence is claimed.
