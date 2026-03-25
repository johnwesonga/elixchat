# ElixChat

A real-time group chat application built with Elixir, Phoenix LiveView, and OTP.

## Features

- **Multiple chat rooms** — four built-in rooms (`#general`, `#elixir`, `#gleam`, `#off-topic`) plus the ability to create custom rooms at runtime
- **Persistent message history** — messages are stored in PostgreSQL and survive server restarts; scroll back to load older messages
- **Real-time messaging** — messages are delivered instantly to all connected users via Phoenix PubSub
- **Typing indicators** — shows who is currently typing, with auto-clear after 2 seconds of inactivity
- **User presence** — tracks who is online in each room using Phoenix Presence; shows join/leave events
- **OTP architecture** — each room runs as its own supervised GenServer process, registered via a Registry and managed by a DynamicSupervisor

## Tech stack

| Layer | Technology |
|---|---|
| Language | Elixir |
| Framework | Phoenix 1.7 + LiveView 1.0 |
| Database | PostgreSQL + Ecto |
| Styling | Tailwind CSS |
| Real-time | Phoenix PubSub + Presence |
| HTTP server | Bandit |

## Getting started

1. Install dependencies and set up the database:

   ```bash
   mix setup
   ```

2. Start the server:

   ```bash
   mix phx.server
   ```

   Or inside IEx:

   ```bash
   iex -S mix phx.server
   ```

3. Visit [http://localhost:4000/rooms](http://localhost:4000/rooms), enter a username, and start chatting.

## Architecture overview

```
RoomManager (GenServer)        — room registry and lifecycle
  └── DynamicSupervisor
        └── RoomServer (per room, via Registry)
              — in-memory message cache (last 50)
              — typing indicator state
              — write-through to PostgreSQL on each message
```

LiveViews subscribe to `room:<id>` PubSub topics and receive pushed updates for new messages, typing changes, and presence diffs without polling.
