defmodule TovutiAi.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :audio_path, :text

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:thread_id])
  end
end
