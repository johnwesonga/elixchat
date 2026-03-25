defmodule MyChatApp.Repo.Migrations.AddAttachmentUrlToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :attachment_url, :string
    end
  end
end
