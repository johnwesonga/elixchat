defmodule MyChatApp.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :room_id,  :string
    field :username, :string
    field :content,  :string
    field :type,     :string, default: "user"

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:room_id, :username, :content, :type])
    |> validate_required([:room_id, :username, :content, :type])
  end
end
