defmodule TovutiAi.Repo.Migrations.AddDeletedAtToThreads do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      add :deleted_at, :utc_datetime, null: true
    end
  end
end
