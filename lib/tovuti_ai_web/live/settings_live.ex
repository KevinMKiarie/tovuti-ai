defmodule TovutiAiWeb.SettingsLive do
  use TovutiAiWeb, :live_view

  require Logger

  alias TovutiAi.VoiceClones
  alias TovutiAi.UserPreferences
  alias TovutiAi.Contacts

  @popular_models [
    %{name: "llama3.1:8b", label: "Llama 3.1 8B", size: "~4.7 GB", description: "Strong tool-calling support — recommended for voice actions"},
    %{name: "phi3:mini", label: "Phi-3 Mini", size: "~2.3 GB", description: "Microsoft's efficient small model"},
    %{name: "qwen2.5:7b", label: "Qwen 2.5 7B", size: "~4.7 GB", description: "Alibaba's balanced 7B model"},
    %{name: "qwen2.5:3b", label: "Qwen 2.5 3B", size: "~2.0 GB", description: "Qwen lightweight variant"},
    %{name: "llama3.2:3b", label: "Llama 3.2 3B", size: "~2.0 GB", description: "Meta's compact instruction model"},
    %{name: "llama3.2:1b", label: "Llama 3.2 1B", size: "~0.9 GB", description: "Ultra-light Meta model"},
    %{name: "mistral:7b", label: "Mistral 7B", size: "~4.1 GB", description: "Fast and capable 7B model"},
    %{name: "gemma2:2b", label: "Gemma 2 2B", size: "~1.6 GB", description: "Google's compact 2B model"},
    %{name: "deepseek-r1:7b", label: "DeepSeek R1 7B", size: "~4.7 GB", description: "Reasoning-focused model"}
  ]

  @tts_param_keys %{
    "exaggeration" => :tts_exaggeration,
    "cfg_weight"   => :tts_cfg_weight,
    "pace"         => :tts_pace
  }

  @default_preview "Hello, I'm Tovuti, your local AI assistant. How can I help you today?"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :load_data)

    socket =
      socket
      |> assign(
        models: [],
        voices: [],
        voice_templates: [],
        active_model: Application.get_env(:tovuti_ai, :ollama_model),
        active_voice_id: Application.get_env(:tovuti_ai, :active_voice_id),
        active_template: Application.get_env(:tovuti_ai, :active_template),
        tts_exaggeration: Application.get_env(:tovuti_ai, :tts_exaggeration, 0.5),
        tts_cfg_weight: Application.get_env(:tovuti_ai, :tts_cfg_weight, 0.5),
        tts_pace: Application.get_env(:tovuti_ai, :tts_pace, 1.0),
        pulling: %{},
        loading: true,
        tab: "models",
        preview_text: @default_preview,
        preview_loading: false,
        upload_loading: false,
        upload_error: nil,
        actions_enabled: Application.get_env(:tovuti_ai, :actions_enabled, false),
        calcom_api_key: Application.get_env(:tovuti_ai, :calcom_api_key, ""),
        calcom_username: Application.get_env(:tovuti_ai, :calcom_username, ""),
        connector_loading: false,
        gmail_connected: false,
        whatsapp_state: "unknown",
        whatsapp_qr: nil,
        contacts: [],
        contact_name: "",
        contact_phone: "",
        contact_error: nil
      )
      |> allow_upload(:voice_clip,
        accept: ~w(.wav .mp3),
        max_entries: 1,
        max_file_size: 50_000_000
      )

    {:ok, socket}
  end


  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("select_model", %{"name" => name}, socket) do
    Application.put_env(:tovuti_ai, :ollama_model, name)
    persist(socket, %{ollama_model: name})
    {:noreply, assign(socket, active_model: name)}
  end

  def handle_event("pull_model", %{"name" => name}, socket) do
    if Map.has_key?(socket.assigns.pulling, name) do
      {:noreply, socket}
    else
      pid = self()
      pulling = Map.put(socket.assigns.pulling, name, %{status: "connecting…", percent: 0, done: false})
      Task.start(fn -> pull_model(pid, name) end)
      {:noreply, assign(socket, pulling: pulling)}
    end
  end

  def handle_event("update_tts_param", %{"param" => param, "value" => value}, socket) do
    with config_key when not is_nil(config_key) <- Map.get(@tts_param_keys, param),
         {float_val, _} <- Float.parse(value) do
      Application.put_env(:tovuti_ai, config_key, float_val)
      persist(socket, %{config_key => float_val})
      {:noreply, assign(socket, [{config_key, float_val}])}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_voice", %{"id" => id}, socket) do
    voice = Enum.find(socket.assigns.voices, &(&1.id == id))

    if voice do
      Application.put_env(:tovuti_ai, :active_voice_id, id)
      Application.put_env(:tovuti_ai, :active_voice_path, voice.clip_path)
      Application.put_env(:tovuti_ai, :active_template, nil)
      Application.put_env(:tovuti_ai, :active_kokoro_voice, nil)
      persist(socket, %{
        active_voice_id: id,
        active_voice_path: voice.clip_path,
        active_template: nil,
        active_kokoro_voice: nil
      })
      {:noreply, assign(socket, active_voice_id: id, active_template: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("use_default_voice", _params, socket) do
    Application.put_env(:tovuti_ai, :active_voice_id, nil)
    Application.put_env(:tovuti_ai, :active_voice_path, nil)
    Application.put_env(:tovuti_ai, :active_template, nil)
    Application.put_env(:tovuti_ai, :active_kokoro_voice, nil)
    persist(socket, %{
      active_voice_id: nil,
      active_voice_path: nil,
      active_template: nil,
      active_kokoro_voice: nil
    })
    {:noreply, assign(socket, active_voice_id: nil, active_template: nil)}
  end

  def handle_event("select_template", %{"id" => template_id}, socket) do
    template = Enum.find(socket.assigns.voice_templates, &(&1["id"] == template_id))
    Logger.info("[SettingsLive] select_template id=#{template_id}, found=#{not is_nil(template)}, templates_count=#{length(socket.assigns.voice_templates)}")

    if template do
      clip_path = template["clip_path"]
      kokoro_voice = template["kokoro_voice"]
      Logger.info("[SettingsLive] setting active_voice_path=#{inspect(clip_path)}, kokoro_voice=#{inspect(kokoro_voice)}")
      Application.put_env(:tovuti_ai, :active_template, template_id)
      Application.put_env(:tovuti_ai, :active_voice_path, clip_path)
      Application.put_env(:tovuti_ai, :active_kokoro_voice, kokoro_voice)
      Application.put_env(:tovuti_ai, :active_voice_id, nil)
      persist(socket, %{
        active_template: template_id,
        active_voice_path: clip_path,
        active_kokoro_voice: kokoro_voice,
        active_voice_id: nil
      })
      {:noreply, assign(socket, active_template: template_id, active_voice_id: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_voice", %{"name" => raw_name}, socket) do
    name = String.trim(raw_name)

    cond do
      name == "" ->
        {:noreply, assign(socket, upload_error: "Voice name is required")}

      socket.assigns.uploads.voice_clip.entries == [] ->
        Logger.warning("[SettingsLive] upload_voice fired but voice_clip entries are empty")
        {:noreply, assign(socket, upload_error: "Please select an audio file")}

      true ->
        pid = self()
        current_scope = scope(socket)

        consumed =
          consume_uploaded_entries(socket, :voice_clip, fn %{path: tmp_path}, _entry ->
            {:ok, File.read!(tmp_path)}
          end)

        case consumed do
          [content] ->
            Task.start(fn -> save_voice_clone(pid, current_scope, name, content) end)
            {:noreply, assign(socket, upload_loading: true, upload_error: nil)}

          _ ->
            {:noreply, assign(socket, upload_error: "File read failed. Please try again.")}
        end
    end
  end

  def handle_event("delete_voice", %{"id" => id}, socket) do
    voice = VoiceClones.get_voice!(scope(socket), id)

    if socket.assigns.active_voice_id == id do
      Application.put_env(:tovuti_ai, :active_voice_id, nil)
      Application.put_env(:tovuti_ai, :active_voice_path, nil)
      persist(socket, %{active_voice_id: nil, active_voice_path: nil})
    end

    filename = Path.basename(voice.clip_path)
    Task.start(fn ->
      Req.delete("#{ai_service_url()}/voices/#{filename}", receive_timeout: 5_000)
    end)

    VoiceClones.delete_voice(voice)

    updated_voices = Enum.reject(socket.assigns.voices, &(&1.id == id))
    active_voice_id = if socket.assigns.active_voice_id == id, do: nil, else: socket.assigns.active_voice_id

    {:noreply, assign(socket, voices: updated_voices, active_voice_id: active_voice_id)}
  end

  def handle_event("update_preview_text", %{"text" => text}, socket) do
    {:noreply, assign(socket, preview_text: text)}
  end

  def handle_event("preview_voice", _params, socket) do
    if socket.assigns.preview_loading do
      {:noreply, socket}
    else
      pid = self()

      %{
        preview_text: text,
        tts_exaggeration: exaggeration,
        tts_cfg_weight: cfg_weight,
        tts_pace: pace
      } = socket.assigns

      kokoro_voice = Application.get_env(:tovuti_ai, :active_kokoro_voice)
      active_path = if kokoro_voice, do: nil, else: active_voice_path(socket)

      Task.start(fn -> synthesize_preview(pid, text, exaggeration, cfg_weight, pace, active_path, kokoro_voice) end)
      {:noreply, assign(socket, preview_loading: true)}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("toggle_actions", _params, socket) do
    enabled = !socket.assigns.actions_enabled
    Application.put_env(:tovuti_ai, :actions_enabled, enabled)
    persist(socket, %{actions_enabled: enabled})
    {:noreply, assign(socket, actions_enabled: enabled)}
  end

  def handle_event("save_calcom_key", %{"key" => key}, socket) do
    key = String.trim(key)
    Application.put_env(:tovuti_ai, :calcom_api_key, key)
    persist(socket, %{calcom_api_key: key})
    {:noreply, assign(socket, calcom_api_key: key) |> put_flash(:info, "Cal.com API key saved")}
  end

  def handle_event("save_calcom_username", %{"username" => username}, socket) do
    username = String.trim(username)
    Application.put_env(:tovuti_ai, :calcom_username, username)
    persist(socket, %{calcom_username: username})
    {:noreply, assign(socket, calcom_username: username) |> put_flash(:info, "Cal.com username saved")}
  end

  def handle_event("update_contact_fields", %{"name" => name, "phone" => phone}, socket) do
    {:noreply, assign(socket, contact_name: name, contact_phone: phone)}
  end

  def handle_event("add_contact", %{"name" => name, "phone" => phone}, socket) do
    name = String.trim(name)
    phone = String.trim(phone)

    case Contacts.create(scope(socket).user.id, %{name: name, phone: phone}) do
      {:ok, contact} ->
        {:noreply,
         assign(socket,
           contacts: socket.assigns.contacts ++ [contact],
           contact_name: "",
           contact_phone: "",
           contact_error: nil
         )}

      {:error, changeset} ->
        msg = changeset.errors |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end) |> Enum.join(", ")
        {:noreply, assign(socket, contact_error: msg)}
    end
  end

  def handle_event("delete_contact", %{"id" => id}, socket) do
    {id_int, _} = Integer.parse(id)
    Contacts.delete(scope(socket).user.id, id_int)
    {:noreply, assign(socket, contacts: Enum.reject(socket.assigns.contacts, &(&1.id == id_int)))}
  end

  def handle_event("connect_gmail", _params, socket) do
    pid = self()
    Task.start(fn ->
      url = ai_service_url()
      case Req.get("#{url}/actions/gmail/auth_url", receive_timeout: 5_000) do
        {:ok, %{status: 200, body: %{"url" => auth_url}}} ->
          send(pid, {:gmail_auth_url, auth_url})
        {:ok, %{status: _, body: %{"detail" => msg}}} ->
          send(pid, {:gmail_auth_error, msg})
        _ ->
          send(pid, {:gmail_auth_error, "Could not reach ai_service"})
      end
    end)
    {:noreply, assign(socket, connector_loading: true)}
  end

  def handle_event("check_gmail_status", _params, socket) do
    pid = self()
    Task.start(fn ->
      url = ai_service_url()
      case Req.get("#{url}/actions/gmail/status", receive_timeout: 5_000) do
        {:ok, %{status: 200, body: %{"connected" => connected}}} ->
          send(pid, {:gmail_status, connected})
        _ ->
          send(pid, {:gmail_status, false})
      end
    end)
    {:noreply, socket}
  end

  def handle_event("refresh_whatsapp", _params, socket) do
    pid = self()
    Task.start(fn ->
      url = ai_service_url()
      case Req.get("#{url}/actions/whatsapp/status", receive_timeout: 8_000) do
        {:ok, %{status: 200, body: body}} ->
          send(pid, {:whatsapp_status, body})
        _ ->
          send(pid, {:whatsapp_status, %{"connected" => false, "state" => "error"}})
      end
    end)
    {:noreply, assign(socket, connector_loading: true)}
  end

  def handle_event("get_whatsapp_qr", _params, socket) do
    pid = self()
    Task.start(fn ->
      url = ai_service_url()
      case Req.get("#{url}/actions/whatsapp/qr", receive_timeout: 15_000) do
        {:ok, %{status: 200, body: body}} ->
          send(pid, {:whatsapp_qr, body})
        {:ok, %{status: _, body: %{"detail" => msg}}} ->
          send(pid, {:connector_error, msg})
        _ ->
          send(pid, {:connector_error, "Failed to get QR code"})
      end
    end)
    {:noreply, assign(socket, connector_loading: true)}
  end

  defp scope(socket), do: socket.assigns.current_scope

  defp persist(socket, attrs) do
    user_id = scope(socket).user.id
    Task.start(fn -> UserPreferences.update(user_id, attrs) end)
  end

  @impl true
  def handle_info(:load_data, socket) do
    user_id = scope(socket).user.id
    prefs = UserPreferences.get_or_create(user_id)
    UserPreferences.apply_to_env(prefs)

    models = fetch_models()
    voices = VoiceClones.list_voices(scope(socket))
    voice_templates = fetch_voice_templates()
    contacts = Contacts.list(user_id)

    pid = self()
    url = ai_service_url()

    Task.start(fn ->
      case Req.get("#{url}/actions/whatsapp/status", receive_timeout: 8_000) do
        {:ok, %{status: 200, body: body}} -> send(pid, {:whatsapp_status, body})
        _ -> :ok
      end
    end)

    Task.start(fn ->
      case Req.get("#{url}/actions/gmail/status", receive_timeout: 5_000) do
        {:ok, %{status: 200, body: %{"connected" => connected}}} -> send(pid, {:gmail_status, connected})
        _ -> :ok
      end
    end)

    {:noreply,
     assign(socket,
       models: models,
       voices: voices,
       voice_templates: voice_templates,
       contacts: contacts,
       loading: false,
       active_model: prefs.ollama_model || "phi3:mini",
       active_voice_id: prefs.active_voice_id,
       active_template: prefs.active_template,
       tts_exaggeration: prefs.tts_exaggeration || 0.5,
       tts_cfg_weight: prefs.tts_cfg_weight || 0.5,
       tts_pace: prefs.tts_pace || 1.0,
       actions_enabled: prefs.actions_enabled || false,
       calcom_api_key: prefs.calcom_api_key || "",
       calcom_username: prefs.calcom_username || ""
     )}
  end

  def handle_info({:voice_saved, voice}, socket) do
    voices = socket.assigns.voices ++ [voice]
    {:noreply, assign(socket, voices: voices, upload_loading: false, upload_error: nil)}
  end

  def handle_info(:voice_save_error, socket) do
    {:noreply, assign(socket, upload_loading: false, upload_error: "Upload failed - check the audio file format and try again.")}
  end

  def handle_info({:pull_progress, model, %{"status" => "success"}}, socket) do
    pulling = Map.put(socket.assigns.pulling, model, %{status: "done", percent: 100, done: true})
    pid = self()

    Task.start(fn ->
      models = fetch_models()
      send(pid, {:models_refreshed, models})
    end)

    {:noreply, assign(socket, pulling: pulling)}
  end

  def handle_info({:pull_progress, model, %{"total" => total, "completed" => completed} = data}, socket)
      when is_integer(total) and total > 0 do
    percent = min(round(completed / total * 100), 99)
    status = Map.get(data, "status", "pulling")
    entry = %{status: status, percent: percent, done: false}
    {:noreply, assign(socket, pulling: Map.put(socket.assigns.pulling, model, entry))}
  end

  def handle_info({:pull_progress, model, %{"status" => status}}, socket) do
    current = Map.get(socket.assigns.pulling, model, %{percent: 0, done: false})
    entry = Map.merge(current, %{status: status})
    {:noreply, assign(socket, pulling: Map.put(socket.assigns.pulling, model, entry))}
  end

  def handle_info({:pull_progress, _model, _data}, socket), do: {:noreply, socket}

  def handle_info({:pull_error, model, reason}, socket) do
    Logger.error("[SettingsLive] Pull failed for #{model}: #{inspect(reason)}")
    pulling = Map.put(socket.assigns.pulling, model, %{status: "error", percent: 0, done: false})
    {:noreply, assign(socket, pulling: pulling)}
  end

  def handle_info({:models_refreshed, models}, socket) do
    {:noreply, assign(socket, models: models)}
  end

  def handle_info({:preview_ready, audio}, socket) do
    socket =
      socket
      |> assign(preview_loading: false)
      |> push_event("play_audio", %{data: audio})

    {:noreply, socket}
  end

  def handle_info(:preview_error, socket) do
    voice_id = Application.get_env(:tovuti_ai, :active_kokoro_voice)
    socket =
      socket
      |> assign(preview_loading: false)
      |> push_event("speak_preview", %{text: socket.assigns.preview_text, voice_id: voice_id})

    {:noreply, socket}
  end


  def handle_info({:gmail_auth_url, url}, socket) do
    {:noreply, redirect(socket, external: url)}
  end

  def handle_info({:gmail_auth_error, msg}, socket) do
    {:noreply,
     socket
     |> assign(connector_loading: false)
     |> put_flash(:error, "Gmail: #{msg}")}
  end

  def handle_info({:gmail_status, connected}, socket) do
    {:noreply, assign(socket, gmail_connected: connected, connector_loading: false)}
  end

  def handle_info({:whatsapp_status, %{"state" => state}}, socket) do
    {:noreply, assign(socket, whatsapp_state: state, connector_loading: false)}
  end

  def handle_info({:whatsapp_qr, %{"qr_base64" => qr}}, socket) do
    # Start polling every 3s to detect when the user scans the QR
    Process.send_after(self(), :poll_whatsapp_status, 3_000)
    {:noreply, assign(socket, whatsapp_qr: qr, connector_loading: false)}
  end

  def handle_info(:poll_whatsapp_status, socket) do
    # Stop polling once connected or if QR is no longer shown
    if socket.assigns.whatsapp_state == "open" || is_nil(socket.assigns.whatsapp_qr) do
      {:noreply, socket}
    else
      pid = self()
      Task.start(fn ->
        case Req.get("#{ai_service_url()}/actions/whatsapp/status", receive_timeout: 5_000) do
          {:ok, %{status: 200, body: %{"state" => state} = body}} ->
            send(pid, {:whatsapp_poll_result, state, body})
          _ ->
            :ok
        end
      end)
      {:noreply, socket}
    end
  end

  def handle_info({:whatsapp_poll_result, "open", _body}, socket) do
    {:noreply, assign(socket, whatsapp_state: "open", whatsapp_qr: nil)}
  end

  def handle_info({:whatsapp_poll_result, _state, _body}, socket) do
    Process.send_after(self(), :poll_whatsapp_status, 3_000)
    {:noreply, socket}
  end

  def handle_info({:connector_error, msg}, socket) do
    {:noreply,
     socket
     |> assign(connector_loading: false)
     |> put_flash(:error, msg)}
  end

  defp ollama_url do
    Application.get_env(:tovuti_ai, :ollama_url, "http://localhost:11434")
  end

  defp ai_service_url do
    Application.get_env(:tovuti_ai, :ai_service_url, "http://localhost:8000")
  end

  defp active_voice_path(socket) do
    case socket.assigns.active_voice_id do
      nil -> nil
      id ->
        case Enum.find(socket.assigns.voices, &(&1.id == id)) do
          %{clip_path: path} -> path
          nil -> nil
        end
    end
  end

  defp fetch_voice_templates do
    result = Req.get("#{ai_service_url()}/voices/templates", receive_timeout: 5_000)
    Logger.info("[SettingsLive] fetch_voice_templates result=#{inspect(result, limit: 200)}")
    case result do
      {:ok, %{status: 200, body: templates}} when is_list(templates) -> templates
      _ -> []
    end
  end

  defp fetch_models do
    installed_names =
      case Req.get("#{ollama_url()}/api/tags", receive_timeout: 5_000) do
        {:ok, %{status: 200, body: %{"models" => models}}} ->
          MapSet.new(models, & &1["name"])

        _ ->
          MapSet.new()
      end

    Enum.map(@popular_models, fn m ->
      Map.put(m, :installed, MapSet.member?(installed_names, m.name))
    end)
  end

  defp save_voice_clone(pid, scope, name, content) do
    encoded = Base.encode64(content)

    result =
      Req.post("#{ai_service_url()}/voices/upload",
        json: %{data: encoded},
        receive_timeout: 30_000,
        retry: false
      )

    case result do
      {:ok, %{status: 200, body: %{"clip_path" => clip_path}}} ->
        case VoiceClones.create_voice(scope, %{name: name, clip_path: clip_path}) do
          {:ok, voice} -> send(pid, {:voice_saved, voice})
          {:error, changeset} ->
            Logger.error("[SettingsLive] DB insert failed: #{inspect(changeset.errors)}")
            send(pid, :voice_save_error)
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("[SettingsLive] Voice upload HTTP #{status}: #{inspect(body)}")
        send(pid, :voice_save_error)

      {:error, reason} ->
        Logger.error("[SettingsLive] Voice upload request failed: #{inspect(reason)}")
        send(pid, :voice_save_error)
    end
  end

  defp synthesize_preview(pid, text, exaggeration, cfg_weight, pace, audio_prompt_path, voice_id) do
    body =
      %{text: text, exaggeration: exaggeration, cfg_weight: cfg_weight, pace: pace}
      |> then(fn b -> if voice_id, do: Map.put(b, :voice_id, voice_id), else: b end)
      |> then(fn b -> if audio_prompt_path, do: Map.put(b, :audio_prompt_path, audio_prompt_path), else: b end)

    case Req.post("#{ai_service_url()}/tts",
           json: body,
           receive_timeout: 60_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"audio" => audio}}} -> send(pid, {:preview_ready, audio})
      _ -> send(pid, :preview_error)
    end
  end

  defp pull_model(pid, name) do
    result =
      Req.post("#{ollama_url()}/api/pull",
        json: %{name: name, stream: true},
        receive_timeout: 600_000,
        into: fn {:data, chunk}, {req, resp} ->
          chunk
          |> String.split("\n", trim: true)
          |> Enum.each(fn line ->
            case Jason.decode(line) do
              {:ok, data} -> send(pid, {:pull_progress, name, data})
              _ -> :ok
            end
          end)

          {:cont, {req, resp}}
        end
      )

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> send(pid, {:pull_error, name, reason})
    end
  end

  defp fmt(val), do: :erlang.float_to_binary(val * 1.0, [{:decimals, 2}])
end
