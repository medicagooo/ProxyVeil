{
  "pending": [
    {
      "task": "review-repair-v1",
      "event": "push-reviewed-main"
    }
  ],
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
    },
    {
      "evidence": [
        "docs/review-0.1.1.md",
        "docs/validation/engine.json",
        "docs/validation/review-regressions.json",
        "docs/validation/registry.json",
        "docs/validation/ui-failure.json",
        "docs/validation/package-smoke.json",
        "STATE.md"
      ],
      "id": "privacy-review-011",
      "business": "Preserve legal YAML routing and optional WebRTC repair; recover native policy types and filesystem failures",
      "request": "request-review-push",
      "date": "2026-10-10",
      "status": "implemented",
      "implementedAt": "2026-10-10T16:30:34.8230494-04:00",
      "reason": "Independent Standards/Spec review and reproduced recovery defects",
      "deployedAt": null,
      "rules": "Domestic rules unchanged; invalid comma groups rejected before write; no live settings changed in tests; incompatible DNS YAML still refused; no force push",
      "before": "Proxy repair rejected or corrupted some valid rules; WebRTC depended on DNS; snapshot arrays could lose restore type; UI preparation errors escaped",
      "after": "Original list indentation and DoH rules retained; WebRTC independent of DNS selection; structured conflict checks and native type restore; UI retains recovery entry after errors",
      "domain": "desktop privacy",
      "integratedAt": null,
      "affected": [
        "desktop user",
        "repair/restore window",
        "FlClash YAML",
        "Edge policy snapshot"
      ]
    }
  ],
  "records": [
    {
      "id": "initial-v1",
      "events": ".branch-records/initial-v1/events.jsonl",
      "state": ".branch-records/initial-v1/state.json"
    },
    {
      "state": ".branch-records/review-repair-v1/state.json",
      "id": "review-repair-v1",
      "events": ".branch-records/review-repair-v1/events.jsonl"
    }
  ],
  "read": [
    "docs/spec-v1.md"
  ],
  "schema": 1,
  "timezone": "America/Halifax",
  "active": [
    "review-repair-v1"
  ]
}
