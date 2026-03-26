defmodule MyChatAppWeb.ChatLive do
  use MyChatAppWeb, :live_view

  alias MyChatApp.Chat.{RoomServer, RoomManager, Presence, Messages}
  alias MyChatApp.Uploads

  @reaction_emojis ["👍", "❤️", "😂", "😮", "😢"]

  @avatar_colors ~w(
    #ef4444 #f97316 #f59e0b #84cc16
    #22c55e #14b8a6 #3b82f6 #8b5cf6
    #ec4899 #06b6d4 #6366f1 #f43f5e
  )

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

      socket =
        socket
        |> assign(
          room_id:           room_id,
          username:          username,
          messages:          state.messages,
          typing:            state.typing,
          online_users:      [],
          draft:             "",
          typing_ref:        nil,
          oldest_message_id: oldest_id,
          all_loaded:        length(state.messages) < 50,
          reaction_emojis:   @reaction_emojis
        )
        |> allow_upload(:attachment,
          accept: ~w(.jpg .jpeg .png .gif .webp .pdf),
          max_entries: 1,
          max_file_size: 10_000_000
        )

      {:ok, socket}
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

    attachment_urls = consume_uploaded_entries(socket, :attachment, fn %{path: path}, entry ->
      url = Uploads.upload!(path, entry.client_name, entry.client_type)
      {:ok, url}
    end)

    attachment_url = List.first(attachment_urls)

    if String.length(text) > 0 or attachment_url do
      RoomServer.post_message(socket.assigns.room_id, %{
        username:       socket.assigns.username,
        content:        text,
        type:           "user",
        attachment_url: attachment_url
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

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachment, ref)}
  end

  def handle_event("react", %{"id" => id, "emoji" => emoji}, socket) do
    RoomServer.toggle_reaction(socket.assigns.room_id, String.to_integer(id), emoji, socket.assigns.username)
    {:noreply, socket}
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

  def handle_info({:reactions_updated, message_id, reactions}, socket) do
    messages =
      Enum.map(socket.assigns.messages, fn msg ->
        if msg.id == message_id, do: Map.put(msg, :reactions, reactions), else: msg
      end)
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    users =
      Presence.list("room:#{socket.assigns.room_id}")
      |> Map.keys()
    {:noreply, assign(socket, online_users: users)}
  end

  # --- Helpers ---

  defp avatar_color(username) do
    index = username |> String.to_charlist() |> Enum.sum() |> rem(length(@avatar_colors))
    Enum.at(@avatar_colors, index)
  end

  defp avatar_initials(username) do
    username
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp upload_error_to_string(:too_large),      do: "File is too large (max 10 MB)"
  defp upload_error_to_string(:too_many_files),  do: "Only one file at a time"
  defp upload_error_to_string(:not_accepted),    do: "Unsupported file type"

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
            <div class={["flex gap-3 group", if(msg.username == @username, do: "flex-row-reverse", else: "")]}>
              <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 text-white"
                   style={"background-color: #{avatar_color(msg.username)}"}>
                <%= avatar_initials(msg.username) %>
              </div>
              <div class={["max-w-xs", if(msg.username == @username, do: "items-end", else: "items-start"), "flex flex-col gap-1"]}>
                <span class="text-xs text-gray-500"><%= msg.username %></span>
                <div class={[
                  "px-4 py-2 rounded-2xl text-sm leading-relaxed",
                  if(msg.username == @username,
                    do: "bg-indigo-600 rounded-tr-sm",
                    else: "bg-gray-800 rounded-tl-sm")
                ]}>
                  <%= for part <- String.split(msg.content, ~r/(@\w+)/, include_captures: true) do %>
                    <%= if String.starts_with?(part, "@") do %>
                      <span class={[
                        "font-semibold",
                        if(String.downcase(part) == "@#{String.downcase(@username)}",
                          do: "bg-indigo-500/40 text-white rounded px-0.5",
                          else: "text-indigo-400")
                      ]}><%= part %></span>
                    <% else %>
                      <%= part %>
                    <% end %>
                  <% end %>
                </div>
                <%!-- Attachment --%>
                <%= if msg[:attachment_url] do %>
                  <%= if String.match?(msg.attachment_url, ~r/\.(jpg|jpeg|png|gif|webp)$/i) do %>
                    <a href={msg.attachment_url} target="_blank" rel="noopener">
                      <img src={msg.attachment_url}
                           class="mt-1 max-w-xs rounded-xl border border-white/10 cursor-pointer hover:opacity-90 transition-opacity"
                           alt="attachment" />
                    </a>
                  <% else %>
                    <a href={msg.attachment_url} target="_blank" rel="noopener"
                       class="flex items-center gap-2 mt-1 text-xs text-indigo-400 hover:text-indigo-300 underline">
                      📎 Download file
                    </a>
                  <% end %>
                <% end %>
                <%!-- Timestamp --%>
                <%= if msg[:inserted_at] do %>
                  <span class="text-xs text-gray-600">
                    <%= Calendar.strftime(msg.inserted_at, "%H:%M") %>
                  </span>
                <% end %>
                <%!-- Reaction pills --%>
                <div class="flex flex-wrap gap-1 mt-1">
                  <%= for {emoji, users} <- Map.get(msg, :reactions, %{}) do %>
                    <button
                      phx-click="react"
                      phx-value-id={msg.id}
                      phx-value-emoji={emoji}
                      class={[
                        "flex items-center gap-1 px-2 py-0.5 rounded-full text-xs border transition-colors",
                        if(@username in users,
                          do: "bg-indigo-600/30 border-indigo-500 text-white",
                          else: "bg-gray-800 border-white/10 text-gray-400 hover:border-white/30")
                      ]}
                    >
                      <%= emoji %> <%= length(users) %>
                    </button>
                  <% end %>
                  <%!-- Emoji picker --%>
                  <div class="flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                    <%= for emoji <- @reaction_emojis do %>
                      <button
                        phx-click="react"
                        phx-value-id={msg.id}
                        phx-value-emoji={emoji}
                        class="text-xs px-1 py-0.5 rounded hover:bg-gray-700 text-gray-500 hover:text-white transition-colors"
                      ><%= emoji %></button>
                    <% end %>
                  </div>
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
        <%!-- Upload preview --%>
        <%= for entry <- @uploads.attachment.entries do %>
          <div class="flex items-center gap-2 mb-2 text-sm text-gray-300">
            <span class="truncate max-w-xs"><%= entry.client_name %></span>
            <span class="text-gray-500 text-xs"><%= entry.progress %>%</span>
            <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}
                    class="text-gray-500 hover:text-red-400 text-xs">✕</button>
          </div>
        <% end %>
        <%= for err <- upload_errors(@uploads.attachment) do %>
          <p class="text-red-400 text-xs mb-2"><%= upload_error_to_string(err) %></p>
        <% end %>
        <form phx-submit="send_message" phx-change="validate_upload" class="flex gap-3">
          <label class="flex items-center justify-center w-11 h-11 rounded-xl bg-gray-800 border border-white/10 hover:border-white/30 cursor-pointer transition-colors shrink-0">
            📎
            <.live_file_input upload={@uploads.attachment} class="hidden" />
          </label>
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
