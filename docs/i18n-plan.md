# Windows language support

Remove the slogan line from the window and adjust the header spacing. Keep the ProxyVeil title and functional description.

At launch, use the current user's Windows display language: any zh language selects simplified Chinese; other languages use English. Resolve once and pass the selected language through same-user UAC, the UI request and the worker. Regional date/number formats do not choose the language. A language override is available for deterministic tests and command-line launch; no language menu is required.

Translate controls, tooltips, accessibility names, settings, progress, operation results, application errors and permission messages. Store text in keyed English/Chinese resources with positional arguments. Keep machine status IDs, configuration values and snapshot formats compatible. Unknown external exception details remain diagnostic data and may follow the operating system's language.

README.md defaults to English and links README.zh-CN.md. Both explain purpose, entrypoints, use and recovery, with current fixture screenshots in the respective language. Portable packages include both documents and their images.

Scope is Windows. Do not modify or retest the macOS CLI. Tests use isolated configuration and simulated Edge policies; native registry tests only use their existing random temporary test keys. Do not repair real FlClash/Edge, elevate, or restart those applications.

Acceptance covers Chinese/English/other-language selection, worker and UAC locale propagation, bilingual repair/restore and failure flows, missing-key/format checks, readable UI layout and extracted packages. Review standards and specification against the task-start commit c61eea4c4a07a30a1f568b09cee38f60252d9744. Fix findings before a normal push to main and verify the remote commit.
