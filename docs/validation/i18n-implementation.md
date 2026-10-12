# Windows i18n implementation

`src/Localization.ps1` loads keyed resources from `src/Locales/en.psd1` and `zh-CN.psd1`. `Get-PvDisplayCulture` reads the current user's Windows UI language; `Resolve-PvLanguage` maps zh variants to simplified Chinese and everything else to English. Explicit en / zh-CN overrides support launch and deterministic tests. Selection does not change the system language or regional formats.

The Windows API behavior is documented by [GetUserDefaultUILanguage](https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-getuserdefaultuilanguage), retrieved 2026-10-12. If a supplemental locale cannot be represented by CultureInfo, the function falls back to the process UI culture. This fallback is code behavior; it is not separate host acceptance.

`scripts/Launch.ps1` resolves language before same-user UAC and includes it in the encoded child command. `Start-ProxyVeil.ps1` selects resources for XAML, settings, accessibility names and runtime text. The slogan node is removed. The UI adds Language to both request JSON and worker arguments so malformed request-file errors also use the selected language. `Invoke-Worker.ps1` sets that language before reading the request.

`ProxyVeil.Core.psm1::Invoke-PvOperation` preserves its original positional interface and wraps `Invoke-PvOperationCore` with optional request Language selection, restoring the caller's language in finally. Missing Language uses the caller's selected language, initially resolved from the display language. Adapter validation, progress and result text use `Get-PvText` with positional arguments. Machine IDs, profile/policy values and snapshot schemas are unchanged, allowing snapshots made in one language to be restored in another. External exception details and user-defined group/path values retain their original language.

README.md defaults to English and links README.zh-CN.md. Both use current isolated screenshots; provenance is in docs/images/README.md. Build copies both documents, PNGs and the src resource files. Package smoke tests verify reciprocal links/images and run both languages in both editions.

Test-I18n checks language mapping, regional independence, resource keys/arguments, XAML keys, request locale lifetime, TUN/Proxy repair, cross-language restore, rollback, bilingual UI/worker flows and malformed worker requests. Existing Chinese-message tests explicitly choose zh-CN to keep assertions independent of host locale. Test-Desktop now resolves the chosen language for Automation names and child launch. Actual UAC is not executed; locale propagation there is reviewed from code.

Validation reports and review findings will be recorded with this task. Real FlClash/Edge writes and macOS retesting remain out of scope.
