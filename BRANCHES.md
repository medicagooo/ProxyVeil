{
  "pending": [],
  "changes": [
    {
      "status": "implemented",
      "deployedAt": null,
      "request": "request-v1",
      "after": "FlClash/Edge selectable TUN and Proxy configuration repair, glass window, Standard/Admin entrypoints, durable conflict-safe restore and two tested portable packages",
      "business": "Standalone script becomes selectable FlClash TUN/Proxy repair with glass UI, privilege editions and persistent restore",
      "evidence": [
        "docs/spec-v1.md",
        "src/ProxyVeil.Core.psm1",
        "src/Start-ProxyVeil.ps1",
        "docs/validation/engine.json",
        "docs/validation/package-smoke.json",
        "STATE.md"
      ],
      "date": "2026-10-10",
      "domain": "desktop privacy",
      "id": "privacy-v1",
      "implementedAt": "2026-10-10T16:05:22.4086128-04:00",
      "integratedAt": null,
      "before": "CLI script",
      "reason": "Reuse privacy configuration on other Windows machines through an application instead of a standalone script",
      "affected": [
        "desktop user",
        "settings and repair/restore window",
        "FlClash YAML/preferences",
        "HKCU Edge policies"
      ],
      "rules": "Domestic routing retained; Proxy DNS covers Edge; restart required; machine policy conflicts skipped; snapshots kept outside repository; no live-machine repair or remote publication in delivery"
    }
  ],
  "records": [
    {
      "id": "initial-v1",
      "events": ".branch-records/initial-v1/events.jsonl",
      "state": ".branch-records/initial-v1/state.json"
    }
  ],
  "read": [
    "docs/spec-v1.md"
  ],
  "schema": 1,
  "timezone": "America/Halifax",
  "active": []
}
