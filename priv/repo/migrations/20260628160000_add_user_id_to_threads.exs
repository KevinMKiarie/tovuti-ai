defmodule TovutiAi.Repo.Migrations.AddUserIdToThreads do
  use Ecto.Migration

  def change do
    execute "TRUNCATE TABLE messages, threads CASCADE", ""

    alter table(:threads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create index(:threads, [:user_id])
  end
end
