defmodule MyChatAppWeb.RoomsLive do
  use MyChatAppWeb, :live_view

  def mount(_params, _session, socket) do
    rooms = MyChatApp.Chat.RoomManager.list_rooms()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyChatApp.PubSub, "rooms:lobby")
      Enum.each(rooms, fn room ->
        Phoenix.PubSub.subscribe(MyChatApp.PubSub, "room:#{room.id}")
      end)
    end

    unread = Map.new(rooms, fn r -> {r.id, 0} end)
    {:ok, assign(socket, rooms: rooms, username: nil, new_room_name: "", new_room_desc: "", error: nil, unread: unread)}
  end

  def handle_event("set_username", %{"username" => name}, socket) do
    name = String.trim(name)
    if String.length(name) >= 2 do
      {:noreply, assign(socket, username: name, error: nil)}
    else
      {:noreply, assign(socket, error: "Username must be at least 2 characters")}
    end
  end

  def handle_event("create_room", %{"name" => name, "desc" => desc}, socket) do
    case MyChatApp.Chat.RoomManager.create_room(name, desc) do
      {:ok, id}               -> {:noreply, push_navigate(socket, to: "/rooms/#{id}?username=#{socket.assigns.username}")}
      {:error, :already_exists} -> {:noreply, assign(socket, error: "Room already exists")}
    end
  end

  def handle_info({:new_message, msg}, socket) do
    unread = Map.update(socket.assigns.unread, msg.room_id, 1, & &1 + 1)
    {:noreply, assign(socket, unread: unread)}
  end

  def handle_info({:rooms_updated, rooms}, socket) do
    {:noreply, assign(socket, rooms: Enum.sort_by(rooms, & &1.name))}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 text-white p-8">
      <div class="max-w-xl mx-auto">
        <h1 class="text-3xl font-semibold mb-1">Chat Rooms</h1>
        <p class="text-gray-400 mb-8">Pick a room to join</p>

        <%!-- Username gate --%>
        <%= if is_nil(@username) do %>
          <div class="bg-gray-900 rounded-xl p-6 mb-8 border border-white/10">
            <p class="font-medium mb-3">Choose a username to get started</p>
            <form phx-submit="set_username" class="flex gap-2">
              <input name="username" placeholder="your name"
                class="flex-1 bg-gray-800 rounded-lg px-4 py-2 text-sm border border-white/10 focus:outline-none focus:border-white/30"/>
              <button class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded-lg text-sm font-medium transition-colors">
                Set name
              </button>
            </form>
            <%= if @error do %>
              <p class="text-red-400 text-sm mt-2"><%= @error %></p>
            <% end %>
          </div>
        <% else %>
          <p class="text-sm text-gray-400 mb-6">
            Chatting as <span class="text-white font-medium"><%= @username %></span>
          </p>
        <% end %>

        <%!-- Room list --%>
        <div class="space-y-2 mb-8">
          <%= for room <- @rooms do %>
            <.link
              navigate={"/rooms/#{room.id}?username=#{@username}"}
              class={[
                "flex justify-between items-center p-4 rounded-xl border transition-all",
                "bg-gray-900 border-white/10 hover:border-white/30 hover:bg-gray-800",
                if(is_nil(@username), do: "opacity-50 pointer-events-none", else: "")
              ]}
            >
              <div>
                <div class="flex items-center gap-2">
                  <p class="font-medium"><%= room.name %></p>
                  <%= if Map.get(@unread, room.id, 0) > 0 do %>
                    <span class="bg-indigo-600 text-white text-xs font-bold rounded-full px-2 py-0.5">
                      <%= Map.get(@unread, room.id) %>
                    </span>
                  <% end %>
                </div>
                <p class="text-sm text-gray-400"><%= room.description %></p>
              </div>
              <span class="text-xs text-gray-500">Join →</span>
            </.link>
          <% end %>
        </div>

        <%!-- Create room --%>
        <%= if @username do %>
          <div class="bg-gray-900 rounded-xl p-6 border border-white/10">
            <p class="font-medium mb-3">Create a room</p>
            <form phx-submit="create_room" class="space-y-2">
              <input name="name" placeholder="room-name"
                class="w-full bg-gray-800 rounded-lg px-4 py-2 text-sm border border-white/10 focus:outline-none focus:border-white/30"/>
              <input name="desc" placeholder="Description (optional)"
                class="w-full bg-gray-800 rounded-lg px-4 py-2 text-sm border border-white/10 focus:outline-none focus:border-white/30"/>
              <button class="w-full py-2 bg-indigo-600 hover:bg-indigo-500 rounded-lg text-sm font-medium transition-colors">
                Create room
              </button>
            </form>
            <%= if @error do %>
              <p class="text-red-400 text-sm mt-2"><%= @error %></p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
