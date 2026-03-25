defmodule MyChatApp.Chat.RoomManagerTest do
  # async: false — RoomManager is a named singleton; tests must not race each other.
  use MyChatApp.DataCase, async: false

  alias MyChatApp.Chat.RoomManager

  describe "list_rooms/0" do
    test "includes all four fixed rooms" do
      rooms = RoomManager.list_rooms()
      ids   = Enum.map(rooms, & &1.id)

      assert "general"   in ids
      assert "elixir"    in ids
      assert "gleam"     in ids
      assert "off-topic" in ids
    end

    test "returns rooms sorted by name" do
      rooms = RoomManager.list_rooms()
      names = Enum.map(rooms, & &1.name)

      assert names == Enum.sort(names)
    end
  end

  describe "room_exists?/1" do
    test "returns true for a fixed room" do
      assert RoomManager.room_exists?("general")
    end

    test "returns false for an unknown room" do
      refute RoomManager.room_exists?("no-such-room-#{System.unique_integer([:positive])}")
    end
  end

  describe "create_room/2" do
    test "creates a new room and returns {:ok, id}" do
      name = "test-room-#{System.unique_integer([:positive])}"

      assert {:ok, id} = RoomManager.create_room(name, "A test room")
      assert RoomManager.room_exists?(id)
    end

    test "the new room appears in list_rooms" do
      name = "test-room-#{System.unique_integer([:positive])}"

      {:ok, id} = RoomManager.create_room(name, "Visible in list")
      ids = RoomManager.list_rooms() |> Enum.map(& &1.id)

      assert id in ids
    end

    test "slugifies the room name into the id" do
      {:ok, id} = RoomManager.create_room("Hello World #{System.unique_integer([:positive])}", "slug test")

      # Spaces and uppercase should be replaced/lowercased
      assert id == String.downcase(id)
      refute String.contains?(id, " ")
    end

    test "returns {:error, :already_exists} for a duplicate name" do
      name = "dupe-#{System.unique_integer([:positive])}"

      assert {:ok, _}                      = RoomManager.create_room(name, "first")
      assert {:error, :already_exists}     = RoomManager.create_room(name, "second")
    end

    test "broadcasts rooms_updated to the lobby topic" do
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "rooms:lobby")

      name = "lobby-test-#{System.unique_integer([:positive])}"
      RoomManager.create_room(name, "broadcast test")

      assert_receive {:rooms_updated, rooms}
      ids = Enum.map(rooms, & &1.id)
      assert Enum.any?(ids, &String.starts_with?(&1, "lobby-test"))
    end
  end
end
