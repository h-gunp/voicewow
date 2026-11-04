# VoiceMate: a calm practice companion

The user requested a full visual redesign for a friend to deaf and hard-of-hearing people, with active liquid glass, consistent Korean typography and a particularly improved prosody entry screen. This is a draft for review, not a publication. Existing audio, model, script tracking and navigation behavior must remain intact.

## Direction

Use a static pale blue/lilac environment with rounded glass navigation, shell and choice controls. Keep reading, measurements and graphs on opaque white wells. Use Pretendard throughout; meaningful outlined icons accompany Korean labels. Equal prosody choice cards contain an icon, title, short explanation and entry cue. Avoid sound-only instructions, decorative emoji and unsupported accuracy claims.

Tokens: canvas #F1F5FC, ink #172B4D, muted #52647B, action #2F62D6, teal #146B70, decorative lilac #E7E0FF. Container/card/control radii 28/20/16. Body 16px, supporting text 14px, card title 20px, section 22px, mobile heading 30px. These are implementation choices, not user-specified exact values.

## Alternatives considered

Full-screen heavy blur risks readability and rendering cost. A purely flat reskin misses the requested glass character. The selected approach puts glass on navigation and interaction surfaces, and solid backgrounds under essential content; Flutter implements equivalent tokens for future Android use.

## Accessibility and constraints

Minimum 48px/dp targets, visible focus, text plus icons/color, wrapping at narrow widths and large text. Respect reduced motion, high contrast and reduced transparency where supported. No moving backgrounds. Preserve semantic labels and live feedback. Preserve ASR opt-in and license notices. No external code or skill installation, no new transcription service, no audio processing changes. Do not reopen previously blocked browser/HTTP paths. Actual iPhone/Android testing is deferred by the user, not a merge gate.

## References and trust

Read-only external design guidance, not executable dependencies: [Anthropic frontend-design](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md) for intentional hierarchy and compact tokens; [Vercel web interface guidance](https://github.com/vercel-labs/web-interface-guidelines/blob/main/command.md) for semantics, focus, motion and layout checks. Local project requirements and the user's instructions take precedence. No related repository AGENTS.md or .agents/skills was found in the inspected checkout.
