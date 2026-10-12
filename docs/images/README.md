# README image provenance

The six PNGs are 620 × 790 WPF renders from `scripts/Test-I18n.ps1`, generated and inspected on 2026-10-12. Tests use isolated configuration and simulated policy storage. Settings paths and the Chinese proxy group name belong to fixtures, with no live subscriptions, credentials or snapshots shown.

| Packaged image | Source render |
|---|---|
| windows-home.png | docs/validation/i18n-en-idle.png |
| windows-settings.png | docs/validation/i18n-en-settings.png |
| windows-completed.png | docs/validation/i18n-en-completed.png |
| windows-zh-cn-home.png | docs/validation/i18n-zh-CN-idle.png |
| windows-zh-cn-settings.png | docs/validation/i18n-zh-CN-settings.png |
| windows-zh-cn-completed.png | docs/validation/i18n-zh-CN-completed.png |

The slogan was removed from both languages. English README uses English screenshots; the Chinese README uses Chinese screenshots. Later tests may regenerate validation renders with different fixture paths; these images retain the selected documentation renders.

These renders do not establish desktop Acrylic appearance or live network privacy. Build copies only this directory's PNGs. Package tests check both READMEs, reciprocal language links and all referenced images before bilingual isolated repair / restore.
