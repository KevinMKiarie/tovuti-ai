defmodule TovutiAi.UserPreferences.UserPreference do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    field :ollama_model, :string, default: "phi3:mini"
    field :actions_enabled, :boolean, default: false
    field :calcom_api_key, :string, default: ""
    field :calcom_username, :string, default: ""
    field :active_voice_id, :string
    field :active_voice_path, :string
    field :active_template, :string
    field :active_kokoro_voice, :string
    field :tts_exaggeration, :float, default: 0.5
    field :tts_cfg_weight, :float, default: 0.5
    field :tts_pace, :float, default: 1.0
    belongs_to :user, TovutiAi.Accounts.User
    timestamps()
  end

  @fields [
    :ollama_model, :actions_enabled, :calcom_api_key, :calcom_username,
    :active_voice_id, :active_voice_path, :active_template, :active_kokoro_voice,
    :tts_exaggeration, :tts_cfg_weight, :tts_pace
  ]

  def changeset(pref, attrs) do
    cast(pref, attrs, @fields)
  end
end
