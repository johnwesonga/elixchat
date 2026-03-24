defmodule MyChatAppWeb.ChatLive do
  use MyChatAppWeb, :live_view

  alias MyChatApp.Chat.{RoomServer, RoomManager, Presence, Messages}

  @typing_timeout 2_000

  def mount(%{"id" => room_id} = params, _session, socket) do
    username = Map.get(params, "username", "anonymous")

    unless RoomManager.room_exists?(room_id) do
      {:ok, push_navigate(socket, to: "/rooms")}
    else
      if connected?(socket) do
        topic = "room:#{room_id}"
        Phoenix.PubSub.subscribe(MyChatApp.PubSub, topic)

        {:ok, _} = Presence.track(self(), topic, username, %{
          username: username,
          joined_at: System.system_time(:second)
        })

        RoomServer.post_message(room_id, %{
          username: "system",
          content:  "#{username} joined",
          type:     "system"
        })
      end

      state = case RoomServer.get_state(room_id) do
        {:error, _} -> %{messages: [], typing: []}
        s           -> s
      end

      oldest_id = state.messages |> List.first() |> case do
        nil -> nil
        msg -> msg.id
      end

      {:ok,
        assign(socket,
          room_id:           room_id,
          username:          username,
          messages:          state.messages,
          typing:            state.typing,
          online_users:      [],
          draft:             "",
          typing_ref:        nil,
          oldest_message_id: oldest_id,
          all_loaded:        length(state.messages) < 50
        )}
    end
  end

  def terminate(_reason, %{assigns: %{room_id: room_id, username: username}} = _socket) do
    RoomServer.post_message(room_id, %{
      username: "system",
      content:  "#{username} left",
      type:     "system"
    })
    RoomServer.set_typing(room_id, username, false)
  end

  # --- Events ---

  def handle_event("send_message", %{"text" => text}, socket) do
    text = String.trim(text)
    if String.length(text) > 0 do
      RoomServer.post_message(socket.assigns.room_id, %{
        username: socket.assigns.username,
        content:  text,
        type:     "user"
      })
      RoomServer.set_typing(socket.assigns.room_id, socket.assigns.username, false)
    end
    {:noreply, assign(socket, draft: "", typing_ref: nil)}
  end

  def handle_event("load_more", _params, socket) do
    %{room_id: room_id, oldest_message_id: oldest_id, messages: messages} = socket.assigns
    older = Messages.list_before(room_id, oldest_id)

    case older do
      [] ->
        {:noreply, assign(socket, all_loaded: true)}
      _ ->
        new_oldest_id = older |> List.first() |> Map.get(:id)
        {:noreply, assign(socket,
          messages:          older ++ messages,
          oldest_message_id: new_oldest_id,
          all_loaded:        length(older) < 30
        )}
    end
  end

  def handle_event("typing", %{"value" => text}, socket) do
    %{room_id: room_id, username: username, typing_ref: ref} = socket.assigns

    # cancel previous auto-stop timer
    if ref, do: Process.cancel_timer(ref)

    RoomServer.set_typing(room_id, username, true)

    # auto-clear typing indicator after 2s of no keystrokes
    new_ref = Process.send_after(self(), :stop_typing, @typing_timeout)

    {:noreply, assign(socket, draft: text, typing_ref: new_ref)}
  end

  # --- Info ---

  def handle_info({:new_message, msg}, socket) do
    messages = socket.assigns.messages ++ [msg]
    oldest_id = socket.assigns.oldest_message_id || msg.id
    {:noreply, assign(socket, messages: messages, oldest_message_id: oldest_id)}
  end

  def handle_info({:typing_update, typing}, socket) do
    others = Enum.reject(typing, & &1 == socket.assigns.username)
    {:noreply, assign(socket, typing: others)}
  end

  def handle_info(:stop_typing, socket) do
    RoomServer.set_typing(socket.assigns.room_id, socket.assigns.username, false)
    {:noreply, assign(socket, typing_ref: nil)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    users =
      Presence.list("room:#{socket.assigns.room_id}")
      |> Map.keys()
    {:noreply, assign(socket, online_users: users)}
  end

  # --- Render ---

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-gray-950 text-white">

      <%!-- Header --%>
      <div class="flex items-center justify-between px-6 py-4 border-b border-white/10 bg-gray-900">
        <div class="flex items-center gap-3">
          <.link navigate="/rooms" class="text-gray-400 hover:text-white text-sm">← Rooms</.link>
          <span class="text-gray-600">/</span>
          <h1 class="font-semibold">#<%= @room_id %></h1>
        </div>
        <div class="flex items-center gap-2 text-sm text-gray-400">
          <span class="w-2 h-2 rounded-full bg-green-400 inline-block"></span>
          <%= length(@online_users) %> online
        </div>
      </div>

      <%!-- Messages --%>
      <div id="messages" class="flex-1 overflow-y-auto px-6 py-4 space-y-3"
           phx-hook="ScrollBottom">
        <%= unless @all_loaded do %>
          <div class="flex justify-center py-2">
            <button phx-click="load_more"
                    class="text-xs text-gray-400 hover:text-white border border-white/10 rounded-lg px-4 py-2 transition-colors">
              Load older messages
            </button>
          </div>
        <% end %>
        <%= for msg <- @messages do %>
          <%= if msg.type == "system" do %>
            <div class="text-center text-xs text-gray-600 py-1"><%= msg.content %></div>
          <% else %>
            <div class={["flex gap-3", if(msg.username == @username, do: "flex-row-reverse", else: "")]}>
              <div class="w-8 h-8 rounded-full bg-indigo-600 flex items-center justify-center text-xs font-bold shrink-0">
                <%= String.first(msg.username) |> String.upcase() %>
              </div>
              <div class={["max-w-xs", if(msg.username == @username, do: "items-end", else: "items-start"), "flex flex-col gap-1"]}>
                <span class="text-xs text-gray-500"><%= msg.username %></span>
                <div class={[
                  "px-4 py-2 rounded-2xl text-sm leading-relaxed",
                  if(msg.username == @username,
                    do: "bg-indigo-600 rounded-tr-sm",
                    else: "bg-gray-800 rounded-tl-sm")
                ]}>
                  <%= msg.content %>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

      <%!-- Typing indicator --%>
      <div class="px-6 h-6 flex items-center">
        <%= if length(@typing) > 0 do %>
          <p class="text-xs text-gray-500 italic">
            <%= Enum.join(@typing, ", ") %> <%= if length(@typing) == 1, do: "is", else: "are" %> typing…
          </p>
        <% end %>
      </div>

      <%!-- Input --%>
      <div class="px-6 py-4 border-t border-white/10 bg-gray-900">
        <form phx-submit="send_message" class="flex gap-3">
          <input
            name="text"
            value={@draft}
            phx-keyup="typing"
            placeholder={"Message ##{@room_id}"}
            autocomplete="off"
            class="flex-1 bg-gray-800 rounded-xl px-4 py-3 text-sm border border-white/10 focus:outline-none focus:border-indigo-500 transition-colors"
          />
          <button class="px-5 py-3 bg-indigo-600 hover:bg-indigo-500 rounded-xl text-sm font-medium transition-colors">
            Send
          </button>
        </form>
      </div>

    </div>
    """
  end
end
