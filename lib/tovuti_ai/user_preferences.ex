defmodule TovutiAi.UserPreferences do
  alias TovutiAi.Repo
  alias TovutiAi.UserPreferences.UserPreference

  def get_or_create(user_id) do
    case Repo.get_by(UserPreference, user_id: user_id) do
      nil ->
        {:ok, pref} = Repo.insert(%UserPreference{user_id: user_id})
        pref

      pref ->
        pref
    end
  end

  def update(user_id, attrs) do
    user_id
    |> get_or_create()
    |> UserPreference.changeset(attrs)
    |> Repo.update()
  end

  def apply_to_env(%UserPreference{} = p) do
    Application.put_env(:tovuti_ai, :ollama_model, p.ollama_model || "phi3:mini")
    Application.put_env(:tovuti_ai, :actions_enabled, p.actions_enabled || false)
    Application.put_env(:tovuti_ai, :calcom_api_key, p.calcom_api_key || "")
    Application.put_env(:tovuti_ai, :calcom_username, p.calcom_username || "")
    Application.put_env(:tovuti_ai, :active_voice_id, p.active_voice_id)
    Application.put_env(:tovuti_ai, :active_voice_path, p.active_voice_path)
    Application.put_env(:tovuti_ai, :active_template, p.active_template)
    Application.put_env(:tovuti_ai, :active_kokoro_voice, p.active_kokoro_voice)
    Application.put_env(:tovuti_ai, :tts_exaggeration, p.tts_exaggeration || 0.5)
    Application.put_env(:tovuti_ai, :tts_cfg_weight, p.tts_cfg_weight || 0.5)
    Application.put_env(:tovuti_ai, :tts_pace, p.tts_pace || 1.0)
    p
  end
end
