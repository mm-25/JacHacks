# Sherry — Hackathon Product Brief

## Product statement

Sherry is a personal memory layer that follows a user across AI tools and devices. It gives people one place to save, find, inspect, and remove useful context without trapping that context inside a single assistant.

## The problem

People use different AI tools on web, desktop, and mobile. Useful context—preferences, decisions, research, and project details—gets fragmented across conversations and devices. Users repeat themselves, lose prior decisions, and cannot easily verify where remembered information came from.

## Target user

The first user is an individual power user who regularly switches among AI assistants and devices and wants continuity without giving up visibility or control.

## Core promise

Save once. Find anywhere. See the source. Stay in control.

## Product principles

1. **Source before magic.** Every memory shows its origin and timestamp.
2. **User-owned by default.** Users can add, inspect, edit, and delete their data.
3. **One system, many surfaces.** Web, desktop, and mobile use the same memory model.
4. **Useful before intelligent.** Reliable text search and sync matter more than speculative AI features.
5. **Honest states.** The product says when data is syncing, offline, stale, or unavailable.

## Hackathon personas

### Primary: multi-tool builder

- Uses multiple AI assistants for work.
- Moves between laptop and phone.
- Needs to recover decisions and preferences quickly.
- Cares about provenance and deletion.

### Secondary: researcher or student

- Collects ideas and excerpts over time.
- Needs simple search and source context.
- Wants quick capture on mobile and desktop.

## Jobs to be done

- When I learn or decide something useful, help me save it quickly.
- When I switch devices, show me the same context.
- When I need prior context, help me find it in seconds.
- When I question a memory, show me where and when it came from.
- When I no longer want something stored, let me remove it clearly.

## Core experience

### Web

The command center: browse all memories, search, open source details, create a note, and delete data.

### Desktop

The work companion: access the shared library and trigger quick capture with minimal interruption.

### Mobile

The pocket capture surface: add a note, search the library, and see synchronization status.

## Information model

A memory contains:

- content
- title or generated preview
- source type and platform
- source label or URL when available
- created and updated timestamps
- optional tags
- synchronization state

For the hackathon, a memory is a user-visible saved item—not an automatically inferred fact. This avoids ambiguity and makes the demo trustworthy.

## Primary flows

### Capture

The user enters text, optionally adds a tag, and saves. The interface immediately shows a pending/synced state.

### Browse and search

The user sees a reverse-chronological library and searches by text. Results preserve source and timestamp.

### Inspect

The user opens a memory to read the full content and provenance.

### Delete

The user confirms deletion. The item disappears across surfaces and the result is explicit.

## Experience requirements

- Creating a manual memory takes no more than two intentional actions after entering text.
- Search begins from the main screen on every surface.
- Source and timestamp are visible without opening technical diagnostics.
- Sync feedback uses plain labels such as `Saving`, `Synced`, `Offline`, and `Retry`.
- Empty states teach the user what to do next.
- The design remains usable with keyboard navigation and common mobile accessibility settings.

## What makes the demo compelling

The product should demonstrate continuity, not just three separate apps. The presentation should visibly create content on one surface and retrieve it on another. Provenance and deletion make the concept credible instead of appearing to be a generic notes app.

## Success measures

### Demo success

- Cross-surface create-to-visible latency is under five seconds on a normal connection.
- Search returns the seeded target in under one second after data is loaded.
- The full golden path can be completed in under three minutes.
- A first-time viewer can explain the product in one sentence after the demo.

### Product signals to collect later

- Memories saved per active user.
- Search success rate.
- Cross-device usage rate.
- Time from search to opening a useful result.
- Delete/export usage as a trust signal.

## Product risks

- **Looks like a notes app:** emphasize cross-device continuity, AI-conversation sources, and provenance.
- **Capture scope becomes too large:** keep automatic provider capture as a stretch goal.
- **Three clients drift apart:** share contracts and visual tokens, and test the same golden path.
- **AI output is unreliable:** keep the main demo deterministic; use AI summarization only as an optional enhancement.
- **Privacy questions dominate:** clearly label demo data and provide visible delete behavior.

## Post-hackathon direction

If the prototype validates interest, expand into provider-specific capture, imports, scoped projects, retrieval connectors, user-controlled permissions, retention, export, and richer ranking. These are intentionally not prerequisites for the hackathon proof.

