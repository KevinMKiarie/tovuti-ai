defmodule TovutiAi.Repo.Migrations.CreateVoiceClones do
  use Ecto.Migration

  def change do
    create table(:voice_clones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :clip_path, :string, null: false
      timestamps()
    end
  end
end
