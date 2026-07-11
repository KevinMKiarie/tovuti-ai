defmodule TovutiAi.Repo.Migrations.AddUserIdToVoiceClones do
  use Ecto.Migration

  def change do
    execute "TRUNCATE TABLE voice_clones CASCADE", ""

    alter table(:voice_clones) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create index(:voice_clones, [:user_id])
  end
end
