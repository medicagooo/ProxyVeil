# Windows i18n review

2026-10-12. Base: `c61eea4c4a07a30a1f568b09cee38f60252d9744`. Implementation: `5e183561b8326bed73f7e6c294f6e1abd8ba1634`.

Reviewed `git diff c61eea4...5e18356` in two independent agents using the code-review skill. Specification: `docs/i18n-plan.md`. Standards: user/repository AGENTS instructions, ADR 0001 and the documented UI → worker → Core boundary, plus the skill's code-smell baseline. Reviews were read-only; no application launch, elevation or real configuration writes.

## Standards

No confirmed standards violations or actionable code smells: 0 findings. Current-user identity guards, isolated fixtures and explicit repair boundaries remain. The operation wrapper preserves the positional contract and restores caller language in finally. Status IDs, configuration values and snapshot structures are invariant. Build includes resources, both READMEs, images and the missing-runtime message script. Resource files have UTF-8 BOM for Windows PowerShell 5 compatibility. Purpose, data flow and side effects are documented in i18n-implementation.md.

## Spec

No actionable specification mismatch: 0 findings. The slogan is removed; display language selects simplified Chinese or English; selected language propagates through launch/UAC, UI and worker. Worker selection precedes request reading, covering malformed requests. Application text is resource-backed, and snapshots restore across languages. English README is default; both documents link each other and use the corresponding screenshots. Package tests exercise both languages and editions. macOS code is unchanged.

Actual UAC was not executed. Language propagation in its encoded command was checked from code. Read-only Windows PowerShell 5 probes loaded Chinese resources and printed the translated missing-runtime message.

## Repairs and validation

During implementation, the first localization assertion exposed a test-expression precedence error; parenthesizing both joined key lists fixed it. A Windows PowerShell 5 probe then exposed a UTF-8-without-BOM resource parsing failure. Resource BOM and terminating bootstrap errors fixed that path, and English / Chinese probes passed. Worker Language arguments were added so an unreadable request does not revert to the host language.

Desktop screenshot inspection caught a blank native window after those reviews: Automation passed, but all captures lacked controls. The replay pixel check failed with dark=0 and accent=0. The same displayed flow with a 2.5-second delay still failed; software rendering restored the content. A new capture gate failed against the actual old hardware path before the fix. Start-ProxyVeil now selects SoftwareOnly for this window's HwndTarget, preserving DWM Acrylic and the existing fallback. No registry or process-wide rendering setting changes.

Supplemental Standards review found one P2: a uniform navy bitmap met both original text/button thresholds. Test-DesktopCapture first failed on RGB(0,64,128); distinct thresholds then rejected five uniform backgrounds and accepted all six bilingual render images (11 checks). Standards re-review confirmed the finding resolved. Spec supplemental review found 0 mismatches. The reviewers inspected the final rendering/capture files; their only execution was the isolated bitmap regression, with no application or live configuration changes.

The original implementation review above remains pinned to c61eea4...5e18356. Supplemental review covers the subsequent Start-ProxyVeil.ps1 / Test-Desktop.ps1 diff, tests/DesktopCapture.Assertions.ps1 and scripts/Test-DesktopCapture.ps1. It is scoped to the rendering repair and its verification.

Full Windows isolated and package results are in `docs/validation/windows-i18n.json`, including UI, language, desktop and package reruns after the rendering fix. No unresolved review findings. Standards: 1 supplemental finding, fixed and rechecked; Spec: 0. Live Repair / Restore, real UAC and post-repair leakage acceptance remain outside this task; Mac was not retested.
