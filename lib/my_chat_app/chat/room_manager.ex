defmodule MyChatApp.Chat.RoomManager do
  use GenServer

  @fixed_rooms [
    %{id: "general", name: "#general", description: "General chat"},
    %{id: "elixir", name: "#elixir", description: "All things Elixir"},
    %{id: "gleam", name: "#gleam", description: "All things Gleam"},
    %{id: "off-topic", name: "#off-topic", description: "Everything else"}
  ]

  # --- Client API ---

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def list_rooms, do: GenServer.call(__MODULE__, :list_rooms)
  def get_room(id), do: GenServer.call(__MODULE__, {:get_room, id})
  def create_room(name, desc), do: GenServer.call(__MODULE__, {:create_room, name, desc})
  def room_exists?(id), do: GenServer.call(__MODULE__, {:exists?, id})

  # --- Callbacks ---

  def init(_) do
    # rooms = Map.new(fixed_rooms, fn(room) -> {room.id, room} end)
    rooms = Map.new(@fixed_rooms, &{&1.id, &1})

    # start a RoomServer for each fixed room
    Enum.each(@fixed_rooms, fn room ->
      DynamicSupervisor.start_child(
        MyChatApp.Chat.RoomSupervisor,
        {MyChatApp.Chat.RoomServer, room.id}
      )
    end)

    {:ok, %{rooms: rooms}}
  end

  def handle_call(:list_rooms, _from, state) do
    rooms = state.rooms |> Map.values() |> Enum.sort_by(& &1.name)
    {:reply, rooms, state}
  end

  def handle_call({:get_room, id}, _from, state) do
    {:reply, Map.get(state.rooms, id), state}
  end

  def handle_call({:create_room, name, desc}, _from, state) do
    id = name |> String.downcase() |> String.replace(~r/[^a-z0-9-]/, "-")

    if Map.has_key?(state.rooms, id) do
      {:reply, {:error, :already_exists}, state}
    else
      room = %{id: id, name: "##{name}", description: desc}

      {:ok, _pid} =
        DynamicSupervisor.start_child(
          MyChatApp.Chat.RoomSupervisor,
          {MyChatApp.Chat.RoomServer, id}
        )

      new_state = put_in(state.rooms[id], room)

      # notify lobby LiveViews
      Phoenix.PubSub.broadcast(
        MyChatApp.PubSub,
        "rooms:lobby",
        {:rooms_updated, Map.values(new_state.rooms)}
      )

      {:reply, {:ok, id}, new_state}
    end
  end

  def handle_call({:exists?, id}, _from, state) do
    {:reply, Map.has_key?(state.rooms, id), state}
  end
end
