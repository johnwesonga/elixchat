defmodule MyChatApp.Chat.Messages do
  import Ecto.Query
  alias MyChatApp.Repo
  alias MyChatApp.Chat.Message

  @page_size 30

  def list_recent(room_id, limit \\ 50) do
    Message
    |> where([m], m.room_id == ^room_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&to_map/1)
  end

  def list_before(room_id, before_id, limit \\ @page_size) do
    Message
    |> where([m], m.room_id == ^room_id and m.id < ^before_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.map(&to_map/1)
  end

  def insert(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, msg} -> {:ok, to_map(msg)}
      error -> error
    end
  end

  defp to_map(%Message{} = m) do
    %{
      id:             m.id,
      room_id:        m.room_id,
      username:       m.username,
      content:        m.content,
      type:           m.type,
      inserted_at:    m.inserted_at,
      attachment_url: m.attachment_url
    }
  end
end
