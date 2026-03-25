defmodule MyChatApp.Chat.MessagesTest do
  use MyChatApp.DataCase, async: true

  alias MyChatApp.Chat.Messages

  # Unique room IDs per test group to avoid cross-test contamination
  defp room(suffix), do: "test-#{suffix}-#{System.unique_integer([:positive])}"

  describe "insert/1" do
    test "inserts a valid user message and returns a map" do
      assert {:ok, msg} = Messages.insert(%{
        room_id: room("ins"), username: "alice", content: "hello", type: "user"
      })

      assert is_integer(msg.id)
      assert msg.username == "alice"
      assert msg.content  == "hello"
      assert msg.type     == "user"
    end

    test "inserts a system message" do
      assert {:ok, msg} = Messages.insert(%{
        room_id: room("sys"), username: "system", content: "alice joined", type: "system"
      })

      assert msg.type == "system"
    end

    test "returns an error changeset when content is missing" do
      assert {:error, changeset} = Messages.insert(%{
        room_id: room("err"), username: "alice", type: "user"
      })

      assert %{content: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns an error changeset when username is missing" do
      assert {:error, changeset} = Messages.insert(%{
        room_id: room("err"), content: "hi", type: "user"
      })

      assert %{username: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "list_recent/2" do
    test "returns messages in oldest-first order" do
      r = room("recent")
      Messages.insert(%{room_id: r, username: "alice", content: "first",  type: "user"})
      Messages.insert(%{room_id: r, username: "alice", content: "second", type: "user"})
      Messages.insert(%{room_id: r, username: "alice", content: "third",  type: "user"})

      msgs = Messages.list_recent(r, 10)

      assert length(msgs) == 3
      assert Enum.map(msgs, & &1.content) == ["first", "second", "third"]
    end

    test "respects the limit and returns the most recent N" do
      r = room("limit")
      for i <- 1..5, do: Messages.insert(%{room_id: r, username: "u", content: "#{i}", type: "user"})

      msgs = Messages.list_recent(r, 3)

      assert length(msgs) == 3
      # Should be the last 3: 3, 4, 5
      assert Enum.map(msgs, & &1.content) == ["3", "4", "5"]
    end

    test "returns an empty list when the room has no messages" do
      assert Messages.list_recent(room("empty"), 10) == []
    end

    test "only returns messages for the given room" do
      r1 = room("r1")
      r2 = room("r2")
      Messages.insert(%{room_id: r1, username: "u", content: "room1", type: "user"})
      Messages.insert(%{room_id: r2, username: "u", content: "room2", type: "user"})

      msgs = Messages.list_recent(r1, 10)

      assert length(msgs) == 1
      assert hd(msgs).content == "room1"
    end
  end

  describe "list_before/3" do
    test "returns messages older than the given id, oldest-first" do
      r = room("before")
      {:ok, m1} = Messages.insert(%{room_id: r, username: "u", content: "one",   type: "user"})
      {:ok, m2} = Messages.insert(%{room_id: r, username: "u", content: "two",   type: "user"})
      {:ok, m3} = Messages.insert(%{room_id: r, username: "u", content: "three", type: "user"})

      result = Messages.list_before(r, m3.id)
      ids    = Enum.map(result, & &1.id)

      assert m1.id in ids
      assert m2.id in ids
      refute m3.id in ids
    end

    test "returns an empty list when there are no older messages" do
      r = room("no-older")
      {:ok, m1} = Messages.insert(%{room_id: r, username: "u", content: "only", type: "user"})

      assert Messages.list_before(r, m1.id) == []
    end

    test "respects the page limit" do
      r = room("page")
      for i <- 1..10, do: Messages.insert(%{room_id: r, username: "u", content: "#{i}", type: "user"})
      {:ok, last} = Messages.insert(%{room_id: r, username: "u", content: "last", type: "user"})

      result = Messages.list_before(r, last.id, 5)

      assert length(result) == 5
    end
  end
end
