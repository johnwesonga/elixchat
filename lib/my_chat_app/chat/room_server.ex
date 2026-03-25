defmodule MyChatApp.Chat.RoomServer do
  use GenServer
  alias MyChatApp.Chat.Messages
  @max_messages 50

  # --- Client API ---

  def start_link(room_id) do
    GenServer.start_link(__MODULE__, room_id,
      name: {:via, Registry, {MyChatApp.Chat.Registry, room_id}}
    )
  end

  def get_state(room_id),          do: call(room_id, :get_state)
  def post_message(room_id, msg),  do: call(room_id, {:post_message, msg})
  def set_typing(room_id, user, typing?), do: cast(room_id, {:typing, user, typing?})
  def toggle_reaction(room_id, message_id, emoji, username),
    do: cast(room_id, {:react, message_id, emoji, username})

  # --- Callbacks ---

  def init(room_id) do
    messages = Messages.list_recent(room_id, @max_messages)
    state = %{
      room_id:   room_id,
      messages:  Enum.reverse(messages),
      typing:    MapSet.new(),
      reactions: %{}
    }
    {:ok, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, public_state(state), state}
  end

  def handle_call({:post_message, msg}, _from, state) do
    {:ok, message} = Messages.insert(%{
      room_id:  state.room_id,
      username: msg.username,
      content:  msg.content,
      type:     Map.get(msg, :type, "user")
    })
    messages = Enum.take([message | state.messages], @max_messages)
    new_state = %{state | messages: messages}

    broadcast(state.room_id, {:new_message, message})
    {:reply, :ok, new_state}
  end

  def handle_cast({:typing, user, true}, state) do
    new_state = %{state | typing: MapSet.put(state.typing, user)}
    broadcast(state.room_id, {:typing_update, MapSet.to_list(new_state.typing)})
    {:noreply, new_state}
  end

  def handle_cast({:typing, user, false}, state) do
    new_state = %{state | typing: MapSet.delete(state.typing, user)}
    broadcast(state.room_id, {:typing_update, MapSet.to_list(new_state.typing)})
    {:noreply, new_state}
  end

  def handle_cast({:react, message_id, emoji, username}, state) do
    reactions =
      Map.update(state.reactions, message_id, %{emoji => MapSet.new([username])}, fn emojis ->
        Map.update(emojis, emoji, MapSet.new([username]), fn users ->
          if MapSet.member?(users, username),
            do: MapSet.delete(users, username),
            else: MapSet.put(users, username)
        end)
        |> Map.reject(fn {_e, users} -> MapSet.size(users) == 0 end)
      end)

    msg_reactions = Map.get(reactions, message_id, %{}) |> serialize_reactions()
    broadcast(state.room_id, {:reactions_updated, message_id, msg_reactions})
    {:noreply, %{state | reactions: reactions}}
  end

  # --- Private ---

  defp public_state(state) do
    %{
      room_id:  state.room_id,
      messages: Enum.reverse(state.messages),  # oldest first
      typing:   MapSet.to_list(state.typing)
    }
  end

  defp serialize_reactions(emojis) do
    Map.new(emojis, fn {emoji, users} -> {emoji, MapSet.to_list(users)} end)
  end

  defp broadcast(room_id, event) do
    Phoenix.PubSub.broadcast(MyChatApp.PubSub, topic(room_id), event)
  end

  defp topic(room_id), do: "room:#{room_id}"

  defp call(room_id, msg) do
    case Registry.lookup(MyChatApp.Chat.Registry, room_id) do
      [{pid, _}] -> GenServer.call(pid, msg)
      []         -> {:error, :room_not_found}
    end
  end

  defp cast(room_id, msg) do
    case Registry.lookup(MyChatApp.Chat.Registry, room_id) do
      [{pid, _}] -> GenServer.cast(pid, msg)
      []         -> :ok
    end
  end

end
