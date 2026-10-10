# Registry format

BRANCHES.md 为 JSON，字段 records/active/pending/read/changes；state.json 为当前任务要求，events.jsonl 为逐行事件。日期 ISO 8601；首次记录、实现、集成、部署分别存储，未知为 null。时区 America/Halifax。pending 引用任务与 operation 事件；证据为项目相对路径。scripts/Validate-Registry.ps1 核验引用、唯一事件与字段。
