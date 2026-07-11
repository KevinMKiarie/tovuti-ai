defmodule TovutiAi.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :ollama_model, :string, default: "phi3:mini"
      add :actions_enabled, :boolean, default: false
      add :calcom_api_key, :string, default: ""
      add :calcom_username, :string, default: ""
      add :active_voice_id, :string
      add :active_voice_path, :string
      add :active_template, :string
      add :active_kokoro_voice, :string
      add :tts_exaggeration, :float, default: 0.5
      add :tts_cfg_weight, :float, default: 0.5
      add :tts_pace, :float, default: 1.0
      timestamps()
    end

    create unique_index(:user_preferences, [:user_id])
  end
end
