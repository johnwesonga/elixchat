defmodule MyChatApp.Repo do
  use Ecto.Repo,
    otp_app: :my_chat_app,
    adapter: Ecto.Adapters.Postgres
end
