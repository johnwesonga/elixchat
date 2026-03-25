defmodule MyChatApp.Chat.RoomServerTest do
  # async: false so the SQL sandbox runs in shared mode, allowing the
  # RoomServer GenServer process to access the DB without explicit allows.
  use MyChatApp.DataCase, async: false

  alias MyChatApp.Chat.RoomServer

  defp unique_room, do: "test-room-#{System.unique_integer([:positive])}"

  defp start_room(room_id) do
    start_supervised!({RoomServer, room_id})
    room_id
  end

  describe "get_state/1" do
    test "returns empty state for a fresh room" do
      room_id = start_room(unique_room())
      state = RoomServer.get_state(room_id)

      assert state.room_id == room_id
      assert state.messages == []
      assert state.typing   == []
    end

    test "returns :error when the room does not exist" do
      assert {:error, :room_not_found} = RoomServer.get_state("nonexistent-room")
    end
  end

  describe "post_message/2" do
    test "stores the message and returns :ok" do
      room_id = start_room(unique_room())

      assert :ok = RoomServer.post_message(room_id, %{
        username: "alice", content: "hello", type: "user"
      })

      state = RoomServer.get_state(room_id)
      assert length(state.messages) == 1
      assert hd(state.messages).content == "hello"
    end

    test "messages are returned in oldest-first order" do
      room_id = start_room(unique_room())

      RoomServer.post_message(room_id, %{username: "alice", content: "first",  type: "user"})
      RoomServer.post_message(room_id, %{username: "alice", content: "second", type: "user"})

      state    = RoomServer.get_state(room_id)
      contents = Enum.map(state.messages, & &1.content)

      assert contents == ["first", "second"]
    end

    test "persists messages to the database" do
      room_id = start_room(unique_room())

      RoomServer.post_message(room_id, %{username: "alice", content: "persisted", type: "user"})

      db_messages = MyChatApp.Chat.Messages.list_recent(room_id, 10)
      assert length(db_messages) == 1
      assert hd(db_messages).content == "persisted"
    end

    test "broadcasts :new_message to the room topic" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")

      RoomServer.post_message(room_id, %{username: "alice", content: "broadcast me", type: "user"})

      assert_receive {:new_message, msg}
      assert msg.content == "broadcast me"
    end

    test "returns :error when the room does not exist" do
      assert {:error, :room_not_found} =
               RoomServer.post_message("no-such-room", %{username: "u", content: "x", type: "user"})
    end
  end

  describe "set_typing/3" do
    test "adds a user to the typing set" do
      room_id = start_room(unique_room())

      RoomServer.set_typing(room_id, "alice", true)
      # set_typing is a cast — give it a moment to process
      :timer.sleep(50)

      state = RoomServer.get_state(room_id)
      assert "alice" in state.typing
    end

    test "removes a user from the typing set" do
      room_id = start_room(unique_room())

      RoomServer.set_typing(room_id, "alice", true)
      :timer.sleep(50)
      RoomServer.set_typing(room_id, "alice", false)
      :timer.sleep(50)

      state = RoomServer.get_state(room_id)
      refute "alice" in state.typing
    end

    test "setting typing to true is idempotent" do
      room_id = start_room(unique_room())

      RoomServer.set_typing(room_id, "alice", true)
      RoomServer.set_typing(room_id, "alice", true)
      :timer.sleep(50)

      state = RoomServer.get_state(room_id)
      assert state.typing == ["alice"]
    end

    test "broadcasts :typing_update to the room topic" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")

      RoomServer.set_typing(room_id, "alice", true)

      assert_receive {:typing_update, users}
      assert "alice" in users
    end

    test "silently ignores cast to a non-existent room" do
      assert :ok = RoomServer.set_typing("no-such-room", "alice", true)
    end
  end

  describe "post_message/2 with attachment" do
    test "stores attachment_url on the message" do
      room_id = start_room(unique_room())
      url = "https://bucket.s3.us-east-1.amazonaws.com/chat/uuid.png"

      assert :ok = RoomServer.post_message(room_id, %{
        username: "alice", content: "", type: "user", attachment_url: url
      })

      state = RoomServer.get_state(room_id)
      assert hd(state.messages).attachment_url == url
    end

    test "message map includes inserted_at" do
      room_id = start_room(unique_room())

      RoomServer.post_message(room_id, %{username: "alice", content: "hi", type: "user"})

      state = RoomServer.get_state(room_id)
      assert %NaiveDateTime{} = hd(state.messages).inserted_at
    end
  end

  describe "toggle_reaction/4" do
    test "adds a reaction to a message" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")
      :ok = RoomServer.post_message(room_id, %{username: "alice", content: "hi", type: "user"})
      assert_receive {:new_message, msg}
      msg_id = msg.id

      RoomServer.toggle_reaction(room_id, msg_id, "👍", "bob")

      assert_receive {:reactions_updated, ^msg_id, %{"👍" => users}}
      assert "bob" in users
    end

    test "removes a reaction when toggled off" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")
      :ok = RoomServer.post_message(room_id, %{username: "alice", content: "hi", type: "user"})
      assert_receive {:new_message, msg}
      msg_id = msg.id

      RoomServer.toggle_reaction(room_id, msg_id, "👍", "bob")
      assert_receive {:reactions_updated, ^msg_id, _}
      RoomServer.toggle_reaction(room_id, msg_id, "👍", "bob")

      assert_receive {:reactions_updated, ^msg_id, reactions}
      assert Map.get(reactions, "👍", []) == []
    end

    test "multiple users can react with the same emoji" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")
      :ok = RoomServer.post_message(room_id, %{username: "alice", content: "hi", type: "user"})
      assert_receive {:new_message, msg}
      msg_id = msg.id

      RoomServer.toggle_reaction(room_id, msg_id, "❤️", "alice")
      assert_receive {:reactions_updated, ^msg_id, _}
      RoomServer.toggle_reaction(room_id, msg_id, "❤️", "bob")

      assert_receive {:reactions_updated, ^msg_id, %{"❤️" => users}}
      assert "alice" in users
      assert "bob" in users
    end

    test "different emojis are tracked independently" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")
      :ok = RoomServer.post_message(room_id, %{username: "alice", content: "hi", type: "user"})
      assert_receive {:new_message, msg}
      msg_id = msg.id

      RoomServer.toggle_reaction(room_id, msg_id, "👍", "alice")
      assert_receive {:reactions_updated, ^msg_id, _}
      RoomServer.toggle_reaction(room_id, msg_id, "😂", "bob")

      assert_receive {:reactions_updated, ^msg_id, reactions}
      assert Map.has_key?(reactions, "👍")
      assert Map.has_key?(reactions, "😂")
    end

    test "broadcasts :reactions_updated to the room topic" do
      room_id = start_room(unique_room())
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room_id}")
      :ok = RoomServer.post_message(room_id, %{username: "alice", content: "hi", type: "user"})
      assert_receive {:new_message, msg}
      msg_id = msg.id

      RoomServer.toggle_reaction(room_id, msg_id, "👍", "alice")

      assert_receive {:reactions_updated, ^msg_id, reactions}
      assert is_map(reactions)
    end

    test "silently ignores cast to a non-existent room" do
      assert :ok = RoomServer.toggle_reaction("no-such-room", 1, "👍", "alice")
    end
  end

  describe "init/1 — seeding from database" do
    test "seeds in-memory state from persisted messages on start" do
      room_id = unique_room()

      # Pre-populate the DB before starting the server
      MyChatApp.Chat.Messages.insert(%{room_id: room_id, username: "alice", content: "old msg", type: "user"})

      start_room(room_id)

      state = RoomServer.get_state(room_id)
      assert length(state.messages) == 1
      assert hd(state.messages).content == "old msg"
    end
  end
end
