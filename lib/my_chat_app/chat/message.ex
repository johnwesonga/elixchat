defmodule MyChatApp.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :room_id,        :string
    field :username,       :string
    field :content,        :string
    field :type,           :string, default: "user"
    field :attachment_url, :string

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:room_id, :username, :content, :type, :attachment_url])
    |> validate_required([:room_id, :username, :type])
    |> then(fn cs ->
      if get_field(cs, :attachment_url) do
        cs |> put_change(:content, get_field(cs, :content) || "")
      else
        validate_required(cs, [:content])
      end
    end)
  end
end
