# PRD: Sherry Web Platform Dashboard Overhaul

## 1. Overview
The goal of this update is to implement a new Dashboard UI design for the Sherry web platform, integrating the Figma mockups with the existing Jaclang backend API. Additionally, we need to resolve several issues regarding how chat transcripts are displayed, filtered, and cleaned.

This document is intended to be fed directly into an AI agent (e.g., JacHammer assistant or an Antigravity agent in a working Jaclang environment) to execute the code changes.

## 2. Environment Context & Known Issues to Resolve

Before implementing the UI, the agent must be aware of the following backend and environment constraints:

### Issue 2.1: `jac build` Deprecation
- **Problem:** The local machine running `v0.16.7` of the Jac CLI no longer supports the legacy `jac build --client static main.jac` command. 
- **Resolution:** The agent implementing this PRD must compile the `apps/web` components using JacHammer's cloud compiler or a legacy local Jac environment. Do not attempt to rely on standard `npm` or Vite builds for the Jaclang frontend.

### Issue 2.2: The "Summary" Block is Unwanted
- **Problem:** The current detail view of a memory card prioritizes the AI-generated "Conversation Summary" block. The user has explicitly rejected this.
- **Resolution:** In the new Chat Memory modal, **completely remove the "Conversation summary" block**. Do not display it to the user.

### Issue 2.3: Pure Transcript & Scraper Artifacts
- **Problem:** The user wants to see the individual, pure transcript messages when clicking a chat. However, the raw text in the database contains noisy scraper metadata.
- **Resolution:** The UI must fetch the raw transcript using the `get_conversation` endpoint. Before rendering the messages, the frontend MUST apply a regex cleaner to strip out the following scraper artifacts:
  - `<environment_context> ... </environment_context>` blocks
  - `Host notice: ... authorization.`
  - `[scraper.err]`
  - `Retained source order: [number]`

### Issue 2.4: Syncing Missing Memories
- **Problem:** Users have reported only seeing 12 memories on the dashboard, despite their local `~/.sherry/scraped_data.json` having 200+ raw messages.
- **Resolution:** This is expected behavior as the backend groups messages into single "Conversation" memories. Ensure the teammate running the scraper locally executes the `start_sync.sh` daemon so that new local chats are continuously pushed to the D1 database.

---

## 3. UI Implementation Requirements

The agent must update the `apps/web/components` Jaclang codebase to implement the following screens based on the provided designs:

### 3.1 Global Sidebar Navigation
Implement a persistent left sidebar with the following active/inactive states:
- **Logo:** "Sherry" (top left)
- **Navigation Links:**
  - `LayoutDashboard` Icon -> **Dashboard**
  - `MessageSquare` Icon -> **Chat Memory**
  - `Sparkles` Icon -> **Personal Memory**
  - `GitMerge` Icon -> **Connected Conversations**
  - `Activity` Icon -> **Diagnostics**
- **User Profile:** Avatar and name at the bottom, with a "Sign out" button.

### 3.2 Chat Memory Tab (Grid & Filters)
- **Header:** Title "Chat Memory" with a global search input bar below it.
- **Filters Dropdowns:** Place three dropdowns directly below the search bar:
  1. **Platform:** "ChatGPT", "Claude", "Gemini", "Antigravity", "Codex"
  2. **Devices:** "Browser", "Desktop", "Mobile"
  3. **Date Range:** "Last 7 days", "Last 30 days"
- **Grid View:** Display the chats fetched from the `list_memories` API in a multi-column masonry/grid layout. Each card should show:
  - Platform Icon (top left)
  - Title (derived from the first message)
  - Text preview
  - Platform name & "Last active" date at the bottom.

### 3.3 Chat Details Modal (Pure Transcript View)
When a user clicks a card in the Chat Memory grid, open a centered overlay modal:
- **Header Actions:** "Open original chat ↗", "Export JSON", "Delete from Sherry"
- **Body:** **DO NOT** include the summary box. Immediately display the `TRANSCRIPT` header.
- **Messages:** Map over the messages array returned by `get_conversation`.
  - Render each message in a chat bubble layout.
  - Label them "USER" or "ASSISTANT" based on the role.
  - Pass the message text through the regex cleaner (defined in Issue 2.3) before rendering.

### 3.4 Dashboard & Personal Memory Tabs
- Build out the static UI frames for the Dashboard (pie charts, stat grids for "Total Chats", "Most Used Memories", "AI Tool Mix") and the Personal Memory settings forms based precisely on the provided screenshots. Integrate them with backend APIs as endpoints become available.
