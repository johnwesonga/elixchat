# AGENTS.md

Guidance for AI agents working in this repository.

## Project overview

ElixChat is a real-time group chat app built with Elixir, Phoenix LiveView, and OTP. Each chat room is an independent supervised GenServer process. Messages are persisted to PostgreSQL with an in-memory write-through cache per room.

## Commands

```bash
# Install dependencies and create/migrate the database
mix setup

# Run the dev server
mix phx.server

# Run inside IEx
iex -S mix phx.server

# Run all tests
mix test

# Create and run a new migration
mix ecto.gen.migration <name>
mix ecto.migrate

# Rollback the last migration
mix ecto.rollback

# Compile (check for errors without starting the server)
mix compile
```

## Architecture

```
lib/my_chat_app/
  application.ex          — supervision tree root
  chat/
    room_manager.ex       — named GenServer; owns room metadata and starts RoomServers
    room_server.ex        — per-room GenServer; message cache + typing state + DB writes
    presence.ex           — Phoenix Presence module for online user tracking
    message.ex            — Ecto schema for the messages table
    messages.ex           — context module: list_recent/2, list_before/3, insert/1

lib/my_chat_app_web/
  router.ex               — routes: GET /rooms, GET /rooms/:id
  live/
    rooms_live.ex         — room listing and creation UI
    chat_live.ex          — main chat UI; subscribes to room PubSub topics
  components/
    core_components.ex    — shared UI components (inputs, buttons, modals, etc.)
```

**Supervision tree (relevant portion):**
```
MyChatApp.Application
  ├── MyChatApp.Repo
  ├── MyChatApp.PubSub
  ├── MyChatAppWeb.Endpoint
  ├── MyChatApp.Chat.Presence
  ├── MyChatApp.Chat.Registry      (Elixir Registry, keyed by room_id string)
  ├── MyChatApp.Chat.RoomSupervisor (DynamicSupervisor)
  └── MyChatApp.Chat.RoomManager
```

## Key conventions

### Message schema
All messages (in-memory and DB) use these keys:
- `id` — integer primary key (from DB)
- `username` — sender's display name; `"system"` for join/leave events
- `content` — message body text
- `type` — `"user"` or `"system"`

Do not use the old keys `user`, `text`, or `system?` — they were replaced during the persistence refactor.

### Room process lookup
`RoomServer` processes are registered in `MyChatApp.Chat.Registry` by `room_id` string. Always look them up via the `call/2` and `cast/2` private helpers in `room_server.ex`, which handle the `{:error, :room_not_found}` case gracefully.

### PubSub topics
- `"room:<room_id>"` — new messages, typing updates, presence diffs for a specific room
- `"rooms:lobby"` — broadcast when a new room is created (consumed by `RoomsLive`)

### Message persistence
`RoomServer` writes every message to PostgreSQL via `Messages.insert/1` before broadcasting. On startup it seeds its in-memory cache with the last 50 messages via `Messages.list_recent/2`. The in-memory list is stored newest-first; `public_state/1` reverses it to oldest-first before returning.

### Known bug
`RoomManager.handle_call({:create_room, ...})` references `MyApp.Chat.RoomServer` (line 51) instead of `MyChatApp.Chat.RoomServer`. Dynamic room creation will crash until this is fixed.

## Database

- **Dev database:** `my_chat_app_dev` (PostgreSQL, default localhost)
- **Test database:** `my_chat_app_test`
- Credentials are in `config/dev.exs` and `config/test.exs`

## Testing

Tests live in `test/`. Run with `mix test`.

The existing test suite covers HTTP controllers only. When adding new features, prefer integration-style tests that hit a real database (SQL sandbox is configured in `test/support/data_case.ex`). Do not mock the Repo.

## Things to avoid

- Do not add messages to `RoomServer` state without also persisting them via `Messages.insert/1`.
- Do not bypass the Registry lookup — never hold a raw PID to a `RoomServer` across calls.
- Do not use `GenServer.start_link` with a fixed atom name for rooms — they must use `{:via, Registry, ...}` since room names are dynamic strings.
- The `DynamicSupervisor` is `MyChatApp.Chat.RoomSupervisor` — always start child room processes through it, not directly.
