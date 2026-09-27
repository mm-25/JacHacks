# JacHacks Scraper: Unified Data Schema Specification

This document guarantees **100% certainty** on exactly what parameters are currently extracted from your local machine and normalized by the Jaclang daemon into the final `scraped_data.json` payload.

Your database teammates can safely rely on this exact schema to build their tables and sync logic, as it accurately represents the lowest common denominator successfully parsed across all three platforms.

## The Output Array
The `scraped_data.json` file is a flat JSON array of objects. Each object represents a single "message" (either a User Prompt or an AI Output).

### Universal Parameters (Guaranteed on 100% of rows)

```json
{
  "id": "codex-a1b2c3d4-42",
  "content": "Can you make it responsive?",
  "createdAt": "2026-09-26T21:46:15Z",
  "source": {
    "type": "conversation_excerpt",
    "platform": "codex",
    "label": "Codex User"
  }
}
```

### Detailed Field Breakdown

| Field | Type | Description & Platform Variations |
| :--- | :--- | :--- |
| `id` | `String` | A uniquely constructed composite ID guaranteeing no collisions. <br>• **Antigravity**: `{step_index}-{conversation_id}-{role}`<br>• **Claude**: `claude-{session_uuid}-{file_line_index}`<br>• **Codex**: `codex-{session_uuid}-{file_line_index}` |
| `content` | `String` | The raw text of the message. The scraper explicitly filters out internal sync events, context tags (e.g., `<app-context>`), and API errors to ensure this only contains human-readable conversation text. |
| `createdAt` | `String` | ISO-8601 formatted timestamp (e.g., `2026-09-26T21:40:03.000Z`) extracted directly from the origin platform's raw event logs. |
| `source` | `Object` | Nested metadata object describing the origin of the content. |
| `source.type` | `String` | Always strictly `"conversation_excerpt"`. |
| `source.platform` | `String` | The provider of the chat. Strictly enum: `"antigravity"`, `"claude"`, or `"codex"`. |
| `source.label` | `String` | A human-readable display string that combines the role and, when available, the chat name.<br>• **Antigravity**: `"User Prompt"` or `"Antigravity Output"`<br>• **Claude**: `"Claude User: {project_name}"` or `"Claude AI: {project_name}"`<br>• **Codex**: `"Codex User"` or `"Codex AI"` |

### Data Points *NOT* Universally Available
Your teammates should be aware that the following data points are **NOT** available universally across all three platforms, which is why the scraper currently flattens them:
* **Chat Name/Title**: Only Claude organizes logs into named "project" folders. Antigravity and Codex use raw UUIDs for session files, meaning no human-readable chat titles exist in their local logs.
* **Tokens/Cost**: Only Claude and Antigravity log token usage locally; Codex does not consistently expose this in the `sessions` directory.
* **System Prompts**: System prompts are highly platform-specific and are excluded to avoid database clutter. Only standard `user` and `assistant` text blocks are captured. 

## Recommendation for the Backend Team
Create a database table (e.g., `Memories` or `ChatLogs`) with the following schema:
- `id` (Primary Key, String)
- `content` (Text)
- `created_at` (Timestamp)
- `platform` (String/Enum)
- `role` (String/Enum — derived by parsing if `source.label` contains "User" vs "AI")
- `chat_context` (String, Optional — populated by the `{project_name}` slice from Claude's label)
