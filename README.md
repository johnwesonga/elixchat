# ElixChat

A real-time group chat application built with Elixir, Phoenix LiveView, and OTP.

## Features

- **Multiple chat rooms** — four built-in rooms (`#general`, `#elixir`, `#gleam`, `#off-topic`) plus the ability to create custom rooms at runtime
- **Persistent message history** — messages are stored in PostgreSQL and survive server restarts; scroll back to load older messages
- **Real-time messaging** — messages are delivered instantly to all connected users via Phoenix PubSub
- **Typing indicators** — shows who is currently typing, with auto-clear after 2 seconds of inactivity
- **User presence** — tracks who is online in each room using Phoenix Presence; shows join/leave events
- **Message timestamps** — each message bubble shows its send time (`HH:MM`)
- **@mentions** — `@username` tokens are highlighted; your own mentions get a background highlight
- **Unread badges** — room list shows a count of new messages received while browsing the lobby
- **Emoji reactions** — react to any message with 👍 ❤️ 😂 😮 😢; reactions sync in real time and toggle on/off
- **File and image uploads** — attach images (JPG, PNG, GIF, WebP) or files (PDF) to messages; images render inline, other files show a download link; stored in S3
- **OTP architecture** — each room runs as its own supervised GenServer process, registered via a Registry and managed by a DynamicSupervisor

## Tech stack

| Layer | Technology |
|---|---|
| Language | Elixir |
| Framework | Phoenix 1.7 + LiveView 1.0 |
| Database | PostgreSQL + Ecto |
| Styling | Tailwind CSS |
| Real-time | Phoenix PubSub + Presence |
| File storage | AWS S3 (via ExAws) |
| HTTP server | Bandit |

## Getting started

1. Set required environment variables:

   ```bash
   export AWS_ACCESS_KEY_ID=...
   export AWS_SECRET_ACCESS_KEY=...
   export AWS_S3_BUCKET=your-bucket-name
   export AWS_REGION=us-east-1   # optional, defaults to us-east-1
   ```

2. Install dependencies and set up the database:

   ```bash
   mix setup
   ```

3. Start the server:

   ```bash
   mix phx.server
   ```

   Or inside IEx:

   ```bash
   iex -S mix phx.server
   ```

4. Visit [http://localhost:4000/rooms](http://localhost:4000/rooms), enter a username, and start chatting.

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
