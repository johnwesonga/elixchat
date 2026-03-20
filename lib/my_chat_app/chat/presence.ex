defmodule MyChatApp.Chat.Presence do
  use Phoenix.Presence,
    otp_app: :my_chat_app,
    pubsub_server: MyChatApp.PubSub
end
