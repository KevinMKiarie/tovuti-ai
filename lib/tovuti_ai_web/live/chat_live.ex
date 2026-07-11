defmodule TovutiAiWeb.ChatLive do
  use TovutiAiWeb, :live_view

  require Logger

  alias TovutiAi.Conversations
  alias TovutiAi.Actions
  alias TovutiAi.UserPreferences
  alias TovutiAi.Contacts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :load_prefs)

    {:ok,
     assign(socket,
       messages: [],
       current_response: "",
       streaming: false,
       streaming_pid: nil,
       recording: false,
       input: "",
       sidebar_open: false,
       current_thread: nil,
       threads: [],
       voice_mode: false,
       live_voice_active: false,
       voice_session_pid: nil,
       active_model: Application.get_env(:tovuti_ai, :ollama_model, "phi3:mini"),
       actions_enabled: Application.get_env(:tovuti_ai, :actions_enabled, false),
       pending_action: nil,
       action_executing: false,
       cal_embed_open: false,
       cal_embed_event_type: "",
       calcom_username: Application.get_env(:tovuti_ai, :calcom_username, ""),
       compose_draft: nil,
       compose_generating: false,
       compose_editing: false,
       compose_sending: false
     )}
  end

  defp scope(socket), do: socket.assigns.current_scope

  @impl true
  def handle_params(%{"thread_id" => thread_id}, _uri, socket) do
    current_thread = socket.assigns.current_thread

    if current_thread && current_thread.id == thread_id do
      {:noreply, assign(socket, threads: Conversations.list_threads(scope(socket)))}
    else
      case Conversations.get_thread_with_messages(scope(socket), thread_id) do
        nil ->
          {:noreply, push_navigate(socket, to: ~p"/")}

        thread ->
          messages =
            Enum.map(thread.messages, fn m -> %{role: m.role, content: m.content, id: m.id} end)

          {:noreply,
           assign(socket,
             current_thread: thread,
             messages: messages,
             threads: Conversations.list_threads(scope(socket))
           )}
      end
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       current_thread: nil,
       messages: [],
       threads: Conversations.list_threads(scope(socket))
     )}
  end

  @impl true
  def handle_event("submit", %{"query" => query}, socket) when byte_size(query) > 0 do
    {thread, user_msg_id} =
      case socket.assigns.current_thread do
        nil ->
          title = String.slice(query, 0, 80)
          {:ok, t} = Conversations.create_thread(scope(socket), %{title: title})
          {:ok, msg} = Conversations.create_message(%{thread_id: t.id, role: "user", content: query})
          {t, msg.id}

        t ->
          {:ok, msg} = Conversations.create_message(%{thread_id: t.id, role: "user", content: query})
          {t, msg.id}
      end

    messages = socket.assigns.messages ++ [%{role: "user", content: query, id: user_msg_id}]
    pid = self()
    use_tools = socket.assigns.actions_enabled
    {:ok, task_pid} = Task.start(fn -> stream_ollama(pid, messages, use_tools) end)

    socket =
      socket
      |> push_event("stream_cancel", tts_cancel_payload())
      |> assign(
        messages: messages,
        current_response: "",
        streaming: true,
        streaming_pid: task_pid,
        input: "",
        current_thread: thread
      )

    socket =
      if socket.assigns.live_action == :index do
        push_patch(socket, to: ~p"/t/#{thread.id}")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"query" => value}, socket) do
    {:noreply, assign(socket, input: value)}
  end

  def handle_event("keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
    handle_event("submit", %{"query" => socket.assigns.input}, socket)
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  def handle_event("stop_generation", _params, socket) do
    if pid = socket.assigns.streaming_pid do
      Process.exit(pid, :kill)
    end

    partial = socket.assigns.current_response

    socket =
      if partial != "" do
        thread = socket.assigns.current_thread
        if thread do
          pid = self()
          Task.start(fn ->
            case Conversations.create_message(%{thread_id: thread.id, role: "assistant", content: partial}) do
              {:ok, msg} -> send(pid, {:message_saved, msg.id})
              _ -> :ok
            end
          end)
        end
        assign(socket,
          messages: socket.assigns.messages ++ [%{role: "assistant", content: partial, id: nil}],
          streaming: false,
          streaming_pid: nil,
          current_response: ""
        )
      else
        assign(socket, streaming: false, streaming_pid: nil, current_response: "")
      end

    {:noreply, push_event(socket, "stream_cancel", %{voice_id: Application.get_env(:tovuti_ai, :active_kokoro_voice, "af_heart")})}
  end

  def handle_event("edit_message", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    messages = socket.assigns.messages
    msg = Enum.at(messages, index)

    ids_to_delete =
      messages
      |> Enum.drop(index)
      |> Enum.map(& &1[:id])
      |> Enum.reject(&is_nil/1)

    if ids_to_delete != [] do
      Task.start(fn -> Conversations.delete_messages(ids_to_delete) end)
    end

    {:noreply, assign(socket,
      messages: Enum.take(messages, index),
      input: msg.content,
      current_response: ""
    )}
  end

  def handle_event("retry_last", _params, socket) do
    messages = socket.assigns.messages

    {context_messages, last_to_delete} =
      case List.last(messages) do
        %{role: "assistant"} = m -> {Enum.drop(messages, -1), m}
        _ -> {messages, nil}
      end

    if last_to_delete && last_to_delete[:id] do
      Task.start(fn -> Conversations.delete_messages([last_to_delete.id]) end)
    end

    pid = self()
    use_tools = socket.assigns.actions_enabled
    {:ok, task_pid} = Task.start(fn -> stream_ollama(pid, context_messages, use_tools) end)

    socket =
      socket
      |> push_event("stream_cancel", tts_cancel_payload())
      |> assign(
        messages: context_messages,
        streaming: true,
        streaming_pid: task_pid,
        current_response: ""
      )

    {:noreply, socket}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  def handle_event("new_chat", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("load_thread", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/t/#{id}")}
  end

  def handle_event("delete_thread", %{"id" => id}, socket) do
    Conversations.soft_delete_thread(scope(socket), id)
    threads = Conversations.list_threads(scope(socket))

    socket =
      if socket.assigns.current_thread && socket.assigns.current_thread.id == id do
        push_navigate(socket, to: ~p"/")
      else
        assign(socket, threads: threads)
      end

    {:noreply, socket}
  end

  def handle_event("open_settings", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/settings")}
  end

  def handle_event("set_voice_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, voice_mode: mode == "voice")}
  end

  def handle_event("start_live_voice", _params, socket) do
    if socket.assigns.voice_session_pid do
      {:noreply, push_event(socket, "live_voice_ready", %{})}
    else
      pid = self()

      case TovutiAi.VoiceSession.start_link(pid) do
        {:ok, session_pid} ->
          kokoro_voice = Application.get_env(:tovuti_ai, :active_kokoro_voice, "af_heart")
          pace = Application.get_env(:tovuti_ai, :tts_pace, 1.0)
          model = socket.assigns.active_model

          messages =
            Enum.map(socket.assigns.messages, fn m ->
              %{"role" => m.role, "content" => m.content}
            end)

          TovutiAi.VoiceSession.set_context(session_pid, messages,
            model: model,
            voice: kokoro_voice,
            pace: pace
          )

          {:noreply,
           socket
           |> assign(live_voice_active: true, voice_session_pid: session_pid)
           |> push_event("live_voice_ready", %{})}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not connect to voice service")}
      end
    end
  end

  def handle_event("stop_live_voice", _params, socket) do
    if pid = socket.assigns.voice_session_pid do
      Process.exit(pid, :normal)
    end

    {:noreply,
     socket
     |> assign(live_voice_active: false, voice_session_pid: nil)
     |> push_event("stream_cancel", tts_cancel_payload())}
  end

  def handle_event("live_audio_chunk", %{"data" => data}, socket) do
    if pid = socket.assigns.voice_session_pid do
      TovutiAi.VoiceSession.send_audio(pid, data)
    end

    {:noreply, socket}
  end

  def handle_event("live_interrupt", _params, socket) do
    if pid = socket.assigns.voice_session_pid do
      TovutiAi.VoiceSession.interrupt(pid)
    end

    {:noreply, push_event(socket, "stream_cancel", tts_cancel_payload())}
  end

  def handle_event("toggle_actions", _params, socket) do
    enabled = !socket.assigns.actions_enabled
    Application.put_env(:tovuti_ai, :actions_enabled, enabled)
    user_id = scope(socket).user.id
    Task.start(fn -> UserPreferences.update(user_id, %{actions_enabled: enabled}) end)
    {:noreply, assign(socket, actions_enabled: enabled)}
  end

  def handle_event("confirm_action", _params, %{assigns: %{pending_action: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("confirm_action", _params, socket) do
    action = socket.assigns.pending_action
    pid = self()
    Task.start(fn ->
      case Actions.execute(%{"type" => action.type, "params" => action.params}) do
        {:ok, result} -> send(pid, {:action_done, result})
        {:error, msg} -> send(pid, {:action_error, msg})
      end
    end)
    {:noreply, assign(socket, action_executing: true)}
  end

  def handle_event("cancel_action", _params, socket) do
    {:noreply, assign(socket, pending_action: nil, action_executing: false)}
  end

  def handle_event("close_cal_embed", _params, socket) do
    {:noreply, assign(socket, cal_embed_open: false)}
  end

  def handle_event("compose_send", _params, socket) do
    draft = socket.assigns.compose_draft
    if draft && draft.content && draft.recipients != [] do
      phones_csv = Enum.join(draft.recipients, ",")
      content = draft.content
      pid = self()
      Task.start(fn ->
        case Actions.execute(%{"type" => "send_whatsapp", "params" => %{"phone" => phones_csv, "message" => content}}) do
          {:ok, result} -> send(pid, {:compose_sent, result})
          {:error, msg} -> send(pid, {:compose_send_error, msg})
        end
      end)
      {:noreply, assign(socket, compose_sending: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("compose_regenerate", _params, socket) do
    draft = socket.assigns.compose_draft
    if draft do
      model = Application.get_env(:tovuti_ai, :ollama_model, "phi3:mini")
      pid = self()
      Task.start(fn -> generate_compose_content(pid, draft.style, draft.prompt, model) end)
      {:noreply, assign(socket, compose_draft: Map.put(draft, :content, nil), compose_generating: true, compose_editing: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("compose_cancel", _params, socket) do
    {:noreply, assign(socket, compose_draft: nil, compose_generating: false, compose_editing: false, compose_sending: false)}
  end

  def handle_event("compose_toggle_edit", _params, socket) do
    {:noreply, assign(socket, compose_editing: !socket.assigns.compose_editing)}
  end

  def handle_event("update_compose_content", %{"content" => content}, socket) do
    if draft = socket.assigns.compose_draft do
      {:noreply, assign(socket, compose_draft: Map.put(draft, :content, content))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("voice_submit", %{"text" => text}, socket) when byte_size(text) > 0 do
    case voice_command(text, socket) do
      {:command, event} -> handle_event(event, %{}, socket)
      :passthrough -> handle_event("submit", %{"query" => text}, socket)
    end
  end

  def handle_event("voice_submit", _params, socket), do: {:noreply, socket}

  def handle_event("audio_data", %{"data" => base64_audio, "type" => mime_type}, socket) do
    pid = self()

    Task.start(fn ->
      case transcribe_audio(base64_audio, mime_type) do
        {:ok, text} -> send(pid, {:transcription_done, text})
        {:error, reason} -> send(pid, {:transcription_error, reason})
      end
    end)

    {:noreply, assign(socket, recording: false)}
  end

  def handle_event("set_recording", %{"value" => value}, socket) do
    {:noreply, assign(socket, recording: value)}
  end

  def handle_event("transcription_result", %{"text" => text}, socket) when byte_size(text) > 0 do
    handle_event("submit", %{"query" => text}, socket)
  end

  def handle_event("transcription_result", _params, socket), do: {:noreply, socket}

  def handle_event("tts_request", %{"text" => text, "seq" => seq}, socket) do
    kokoro_voice = Application.get_env(:tovuti_ai, :active_kokoro_voice)
    pace = Application.get_env(:tovuti_ai, :tts_pace, 1.0)
    pid = self()

    if kokoro_voice && byte_size(text) > 0 do
      Task.start(fn -> synthesize_tts_chunk(pid, text, kokoro_voice, pace, seq) end)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_prefs, socket) do
    user_id = scope(socket).user.id
    prefs = UserPreferences.get_or_create(user_id)
    UserPreferences.apply_to_env(prefs)

    socket =
      socket
      |> assign(
        active_model: prefs.ollama_model || "phi3:mini",
        actions_enabled: prefs.actions_enabled || false,
        calcom_username: prefs.calcom_username || ""
      )
      |> push_event("set_chat_voice", %{
        voice_id: prefs.active_kokoro_voice || "af_heart",
        kokoro_active: not is_nil(prefs.active_kokoro_voice),
        server_tts: not is_nil(prefs.active_kokoro_voice || prefs.active_voice_path)
      })

    {:noreply, socket}
  end

  def handle_info({:ai_token, _token}, %{assigns: %{streaming: false}} = socket), do: {:noreply, socket}

  def handle_info({:ai_token, token}, socket) do
    socket =
      socket
      |> assign(current_response: socket.assigns.current_response <> token)
      |> push_event("stream_token", %{token: token})

    {:noreply, socket}
  end

  def handle_info(:ai_stream_done, %{assigns: %{streaming: false}} = socket), do: {:noreply, socket}

  def handle_info(:ai_stream_done, socket) do
    full_response = socket.assigns.current_response
    messages = socket.assigns.messages ++ [%{role: "assistant", content: full_response, id: nil}]

    if thread = socket.assigns.current_thread do
      pid = self()
      Task.start(fn ->
        case Conversations.create_message(%{
          thread_id: thread.id,
          role: "assistant",
          content: full_response
        }) do
          {:ok, msg} -> send(pid, {:message_saved, msg.id})
          _ -> :ok
        end
      end)
    end

    active_voice_path = Application.get_env(:tovuti_ai, :active_voice_path)
    kokoro_voice = Application.get_env(:tovuti_ai, :active_kokoro_voice)
    Logger.info("[ChatLive] stream done — kokoro_voice=#{inspect(kokoro_voice)}, active_voice_path=#{inspect(active_voice_path)}")

    tts_active = kokoro_voice || active_voice_path

    if tts_active && is_nil(kokoro_voice) do
      pid = self()
      pace = Application.get_env(:tovuti_ai, :tts_pace, 1.0)
      tts_text = full_response
        |> String.replace(~r/```[\s\S]*?```/, "")
        |> String.replace(~r/[#*_~>`|]/, "")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> String.slice(0, 600)

      exaggeration = Application.get_env(:tovuti_ai, :tts_exaggeration, 0.5)
      cfg_weight = Application.get_env(:tovuti_ai, :tts_cfg_weight, 0.5)
      Task.start(fn -> synthesize_chat_tts(pid, tts_text, exaggeration, cfg_weight, pace, active_voice_path) end)
    end

    socket =
      socket
      |> assign(messages: messages, current_response: "", streaming: false, streaming_pid: nil)
      |> push_event("stream_done", %{chatterbox: not is_nil(tts_active), kokoro: not is_nil(kokoro_voice)})

    {:noreply, socket}
  end

  def handle_info({:message_saved, id}, socket) do
    messages =
      case Enum.find_index(socket.assigns.messages, fn m ->
             m.role == "assistant" && is_nil(m[:id])
           end) do
        nil -> socket.assigns.messages
        i -> List.update_at(socket.assigns.messages, i, &Map.put(&1, :id, id))
      end

    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info({:ai_error, reason}, socket) do
    Logger.error("[ChatLive] AI error: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(streaming: false, current_response: "")
     |> put_flash(:error, "Could not reach Ollama. Is it running on port 11434?")}
  end

  def handle_info({:audio_ready, base64_audio}, socket) do
    {:noreply, push_event(socket, "play_audio", %{data: base64_audio})}
  end

  def handle_info({:audio_error, _reason}, socket), do: {:noreply, socket}

  def handle_info({:audio_chunk_ready, seq, audio}, socket) do
    {:noreply, push_event(socket, "play_audio_chunk", %{seq: seq, data: audio})}
  end

  def handle_info({:audio_chunk_skip, seq}, socket) do
    {:noreply, push_event(socket, "skip_audio_chunk", %{seq: seq})}
  end

  # create_booking opens the Cal.com embed directly without the confirm/cancel flow
  def handle_info({:action_detected, %{type: "create_booking", params: params}}, socket) do
    username = socket.assigns.calcom_username
    event_type = Map.get(params || %{}, "event_type", "")

    {messages, cal_open} =
      if username != "" do
        msg = %{role: "assistant", content: "Opening your Cal.com booking page — pick a time that works for you.", id: nil}
        {socket.assigns.messages ++ [msg], true}
      else
        msg = %{role: "assistant", content: "To create a booking page, please add your Cal.com username in **Settings → Connectors** first.", id: nil}
        {socket.assigns.messages ++ [msg], false}
      end

    {:noreply,
     assign(socket,
       messages: messages,
       cal_embed_open: cal_open,
       cal_embed_event_type: event_type,
       streaming: false,
       streaming_pid: nil,
       current_response: ""
     )}
  end

  def handle_info({:action_detected, %{type: "send_whatsapp", params: params}}, socket) do
    raw_phone = params["phone"] || ""
    user_id = scope(socket).user.id

    {final_params, description} =
      case Contacts.resolve_recipients(user_id, raw_phone) do
        {:ok, resolved} ->
          p = Map.put(params, "phone", resolved)
          {p, Actions.describe("send_whatsapp", p)}

        {:error, unresolved, resolved} ->
          names = Enum.join(unresolved, ", ")
          note = " ⚠ Could not find: #{names}"
          p = if resolved != [], do: Map.put(params, "phone", Enum.join(resolved, ",")), else: params
          {p, Actions.describe("send_whatsapp", p) <> note}
      end

    {:noreply,
     assign(socket,
       pending_action: %{type: "send_whatsapp", params: final_params, description: description},
       streaming: false,
       streaming_pid: nil,
       current_response: ""
     )}
  end

  def handle_info({:action_detected, %{type: "compose_and_send", params: params}}, socket) do
    user_id = scope(socket).user.id
    style = params["style"] || "content"
    prompt = params["prompt"] || ""
    recipients_raw = String.trim(params["recipients"] || "")
    model = Application.get_env(:tovuti_ai, :ollama_model, "phi3:mini")

    {phones, labels} =
      if String.downcase(recipients_raw) in ["all", "everyone", "all contacts"] do
        contacts = Contacts.list(user_id)
        {Enum.map(contacts, & &1.phone), Enum.map(contacts, & &1.name)}
      else
        entries =
          recipients_raw
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        case Contacts.resolve_recipients(user_id, recipients_raw) do
          {:ok, resolved} ->
            phones = resolved |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
            {phones, entries}

          {:error, _unresolved, resolved} ->
            {resolved, entries}
        end
      end

    pid = self()
    Task.start(fn -> generate_compose_content(pid, style, prompt, model) end)

    {:noreply,
     assign(socket,
       compose_draft: %{content: nil, recipients: phones, labels: labels, style: style, prompt: prompt},
       compose_generating: true,
       compose_editing: false,
       compose_sending: false,
       streaming: false,
       streaming_pid: nil,
       current_response: ""
     )}
  end

  def handle_info({:action_detected, %{type: type, params: params}}, socket) do
    description = Actions.describe(type, params)
    {:noreply,
     assign(socket,
       pending_action: %{type: type, params: params, description: description},
       streaming: false,
       streaming_pid: nil,
       current_response: ""
     )}
  end

  def handle_info({:action_done, result}, socket) do
    action = socket.assigns.pending_action
    result_text = Actions.format_result(action.type, result)
    messages = socket.assigns.messages ++ [%{role: "assistant", content: result_text, id: nil}]

    if thread = socket.assigns.current_thread do
      pid = self()
      Task.start(fn ->
        case Conversations.create_message(%{thread_id: thread.id, role: "assistant", content: result_text}) do
          {:ok, msg} -> send(pid, {:message_saved, msg.id})
          _ -> :ok
        end
      end)
    end

    notification = action_notification(action.type, result)
    pid = self()
    Task.start(fn -> speak_notification(pid, notification) end)

    {:noreply,
     assign(socket, pending_action: nil, action_executing: false, messages: messages)}
  end

  def handle_info({:action_error, msg}, socket) do
    {:noreply,
     socket
     |> assign(pending_action: nil, action_executing: false)
     |> put_flash(:error, "Action failed: #{msg}")}
  end

  def handle_info({:compose_ready, content}, socket) do
    draft = socket.assigns.compose_draft
    {:noreply, assign(socket, compose_draft: Map.put(draft, :content, content), compose_generating: false)}
  end

  def handle_info({:compose_error, reason}, socket) do
    Logger.error("[ChatLive] compose error: #{inspect(reason)}")
    {:noreply,
     socket
     |> assign(compose_draft: nil, compose_generating: false)
     |> put_flash(:error, "Could not generate content — check Ollama is running")}
  end

  def handle_info({:compose_sent, _result}, socket) do
    draft = socket.assigns.compose_draft
    count = length(draft.recipients)
    labels_str = Enum.join(draft.labels, ", ")
    result_text = "#{String.capitalize(draft.style)} sent to #{count} contact(s): #{labels_str}"
    messages = socket.assigns.messages ++ [%{role: "assistant", content: result_text, id: nil}]

    if thread = socket.assigns.current_thread do
      pid = self()
      Task.start(fn ->
        case Conversations.create_message(%{thread_id: thread.id, role: "assistant", content: result_text}) do
          {:ok, msg} -> send(pid, {:message_saved, msg.id})
          _ -> :ok
        end
      end)
    end

    notification = "#{String.capitalize(draft.style)} sent to #{Enum.join(draft.labels, " and ")}"
    pid = self()
    Task.start(fn -> speak_notification(pid, notification) end)

    {:noreply,
     assign(socket,
       compose_draft: nil,
       compose_generating: false,
       compose_editing: false,
       compose_sending: false,
       messages: messages
     )}
  end

  def handle_info({:compose_send_error, msg}, socket) do
    {:noreply,
     socket
     |> assign(compose_sending: false)
     |> put_flash(:error, "Failed to send: #{msg}")}
  end

  def handle_info({:transcription_done, text}, socket) do
    case voice_command(text, socket) do
      {:command, event} -> handle_event(event, %{}, socket)
      :passthrough -> {:noreply, assign(socket, input: text)}
    end
  end

  def handle_info({:transcription_error, _reason}, socket) do
    {:noreply, put_flash(socket, :error, "Could not transcribe audio")}
  end

  # ── Live voice session events ─────────────────────────────────────────────

  def handle_info({:voice_transcript, text}, socket) do
    thread =
      case socket.assigns.current_thread do
        nil ->
          title = String.slice(text, 0, 80)
          {:ok, t} = Conversations.create_thread(scope(socket), %{title: title})
          t

        t ->
          t
      end

    {:ok, msg} = Conversations.create_message(%{thread_id: thread.id, role: "user", content: text})
    messages = socket.assigns.messages ++ [%{role: "user", content: text, id: msg.id}]

    socket =
      socket
      |> assign(messages: messages, current_response: "", current_thread: thread)
      |> push_event("stream_cancel", tts_cancel_payload())
      |> push_event("live_transcript", %{text: text})

    socket =
      if socket.assigns.live_action == :index do
        push_patch(socket, to: ~p"/t/#{thread.id}")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:voice_token, token}, socket) do
    socket =
      socket
      |> assign(current_response: socket.assigns.current_response <> token)
      |> push_event("live_token", %{token: token})

    {:noreply, socket}
  end

  def handle_info({:voice_audio_chunk, seq, data}, socket) do
    {:noreply, push_event(socket, "play_audio_chunk", %{seq: seq, data: data})}
  end

  def handle_info({:voice_done, final_seq}, socket) do
    full_response = socket.assigns.current_response
    messages = socket.assigns.messages ++ [%{role: "assistant", content: full_response, id: nil}]

    if thread = socket.assigns.current_thread do
      pid = self()

      Task.start(fn ->
        case Conversations.create_message(%{
               thread_id: thread.id,
               role: "assistant",
               content: full_response
             }) do
          {:ok, saved_msg} -> send(pid, {:message_saved, saved_msg.id})
          _ -> :ok
        end
      end)
    end

    # Update the Python session's conversation context with the new messages
    if pid = socket.assigns.voice_session_pid do
      kokoro_voice = Application.get_env(:tovuti_ai, :active_kokoro_voice, "af_heart")
      pace = Application.get_env(:tovuti_ai, :tts_pace, 1.0)

      updated_messages =
        Enum.map(messages, fn m -> %{"role" => m.role, "content" => m.content} end)

      TovutiAi.VoiceSession.set_context(pid, updated_messages,
        model: socket.assigns.active_model,
        voice: kokoro_voice,
        pace: pace
      )
    end

    {:noreply,
     socket
     |> assign(messages: messages, current_response: "")
     |> push_event("live_done", %{final_seq: final_seq})}
  end

  def handle_info(:voice_speech_start, socket) do
    {:noreply, push_event(socket, "live_speech_start", %{})}
  end

  def handle_info(:voice_processing, socket) do
    {:noreply, push_event(socket, "live_processing", %{})}
  end

  def handle_info(:voice_interrupt_ack, socket) do
    {:noreply,
     socket
     |> assign(current_response: "")
     |> push_event("stream_cancel", tts_cancel_payload())}
  end

  def handle_info(:voice_session_disconnected, socket) do
    {:noreply,
     socket
     |> assign(live_voice_active: false, voice_session_pid: nil)
     |> push_event("voice_session_lost", %{})
     |> put_flash(:error, "Voice connection lost — is the AI service running?")}
  end

  # ── private ────────────────────────────────────────────────────────────────

  defp tts_cancel_payload do
    kokoro_v = Application.get_env(:tovuti_ai, :active_kokoro_voice)
    voice_path = Application.get_env(:tovuti_ai, :active_voice_path)
    %{
      voice_id: kokoro_v || "af_heart",
      kokoro_active: not is_nil(kokoro_v),
      server_tts: not is_nil(kokoro_v || voice_path)
    }
  end

  @confirm_words ~w(send confirm yes okay ok go do it approved proceed)
  @cancel_words  ~w(cancel no stop dismiss abort nope)
  @regen_words   ~w(regenerate retry again another different new)

  defp voice_command(text, socket) do
    cmd = text |> String.downcase() |> String.trim()

    cond do
      socket.assigns.pending_action != nil ->
        cond do
          Enum.any?(@confirm_words, &String.contains?(cmd, &1)) -> {:command, "confirm_action"}
          Enum.any?(@cancel_words,  &String.contains?(cmd, &1)) -> {:command, "cancel_action"}
          true -> :passthrough
        end

      socket.assigns.compose_draft != nil && not socket.assigns.compose_generating ->
        cond do
          Enum.any?(@confirm_words, &String.contains?(cmd, &1)) -> {:command, "compose_send"}
          Enum.any?(@regen_words,   &String.contains?(cmd, &1)) -> {:command, "compose_regenerate"}
          Enum.any?(@cancel_words,  &String.contains?(cmd, &1)) -> {:command, "compose_cancel"}
          true -> :passthrough
        end

      true -> :passthrough
    end
  end

  defp action_notification("send_whatsapp", %{"count" => count}) when is_integer(count) and count > 1 do
    "Message sent to #{count} contacts"
  end
  defp action_notification("send_whatsapp", %{"recipients" => [%{"phone" => phone} | _]}) do
    "Message sent to #{phone}"
  end
  defp action_notification("send_whatsapp", %{"phone" => phone}) do
    "Message sent to #{phone}"
  end
  defp action_notification("send_email", %{"to" => to}) do
    "Email sent to #{to}"
  end
  defp action_notification("reschedule_meeting", _), do: "Meeting rescheduled"
  defp action_notification(_type, _result), do: "Action completed"

  defp speak_notification(pid, text) do
    kokoro_voice = Application.get_env(:tovuti_ai, :active_kokoro_voice)
    active_voice_path = Application.get_env(:tovuti_ai, :active_voice_path)
    pace = Application.get_env(:tovuti_ai, :tts_pace, 1.0)

    cond do
      kokoro_voice ->
        body = %{text: text, voice_id: kokoro_voice, pace: pace}
        case Req.post("#{ai_service_url()}/tts", json: body, receive_timeout: 30_000, retry: false) do
          {:ok, %{status: 200, body: %{"audio" => audio}}} -> send(pid, {:audio_ready, audio})
          _ -> :ok
        end

      active_voice_path ->
        exaggeration = Application.get_env(:tovuti_ai, :tts_exaggeration, 0.5)
        cfg_weight = Application.get_env(:tovuti_ai, :tts_cfg_weight, 0.5)
        synthesize_chat_tts(pid, text, exaggeration, cfg_weight, pace, active_voice_path)

      true ->
        :ok
    end
  end

  defp ollama_url do
    Application.get_env(:tovuti_ai, :ollama_url, "http://localhost:11434")
  end

  defp ai_service_url do
    Application.get_env(:tovuti_ai, :ai_service_url, "http://localhost:8000")
  end

  @system_prompt """
  You are Tovuti, a helpful conversational AI assistant. Respond naturally and directly to the user.
  Only call a tool when the user explicitly asks you to perform an action such as sending a message, scheduling a meeting, or sending an email.
  For all other questions, conversations, or requests for information, respond as plain text without calling any tools.
  """

  defp stream_ollama(pid, messages, use_tools) do
    model = Application.get_env(:tovuti_ai, :ollama_model, "phi3:mini")

    system_msg = %{role: "system", content: @system_prompt}

    payload =
      %{
        model: model,
        messages: [system_msg | Enum.map(messages, fn m -> %{role: m.role, content: m.content} end)],
        stream: true,
        options: %{num_ctx: 2048, num_thread: 4}
      }
      |> then(fn p ->
        if use_tools, do: Map.put(p, :tools, Actions.tools()), else: p
      end)

    result =
      Req.post("#{ollama_url()}/api/chat",
        json: payload,
        receive_timeout: 120_000,
        into: fn {:data, chunk}, {req, resp} ->
          chunk
          |> String.split("\n", trim: true)
          |> Enum.each(fn line ->
            case Jason.decode(line) do
              {:ok, %{"message" => %{"tool_calls" => [call | _]}}} ->
                type = get_in(call, ["function", "name"])
                params = get_in(call, ["function", "arguments"])
                send(pid, {:action_detected, %{type: type, params: params}})

              {:ok, %{"done" => true}} ->
                send(pid, :ai_stream_done)

              {:ok, %{"message" => %{"content" => token}}} when token != "" ->
                send(pid, {:ai_token, token})

              _ ->
                :ok
            end
          end)

          {:cont, {req, resp}}
        end
      )

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> send(pid, {:ai_error, reason})
    end
  end

  defp synthesize_tts_chunk(pid, text, voice_id, pace, seq) do
    clean = text |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 400)
    body = %{text: clean, voice_id: voice_id, pace: pace}

    case Req.post("#{ai_service_url()}/tts", json: body, receive_timeout: 30_000, retry: false) do
      {:ok, %{status: 200, body: %{"audio" => audio}}} ->
        send(pid, {:audio_chunk_ready, seq, audio})
      _ ->
        send(pid, {:audio_chunk_skip, seq})
    end
  end

  defp synthesize_chat_tts(pid, text, exaggeration, cfg_weight, pace, audio_prompt_path) do
    body = %{
      text: text,
      exaggeration: exaggeration,
      cfg_weight: cfg_weight,
      pace: pace,
      audio_prompt_path: audio_prompt_path
    }

    Logger.info("[ChatLive] calling TTS with audio_prompt_path=#{inspect(audio_prompt_path)}, text_len=#{String.length(text)}")

    result = Req.post("#{ai_service_url()}/tts",
      json: body,
      receive_timeout: 120_000,
      retry: false
    )

    case result do
      {:ok, %{status: 200, body: %{"audio" => audio}}} ->
        Logger.info("[ChatLive] TTS success, audio_bytes=#{byte_size(Base.decode64!(audio))}")
        send(pid, {:audio_ready, audio})
      other ->
        Logger.error("[ChatLive] TTS failed: #{inspect(other)}")
        send(pid, {:audio_error, :tts_failed})
    end
  end

  defp generate_compose_content(pid, style, prompt, model) do
    system = """
    You are a skilled writing assistant. Generate well-crafted #{style} content.
    Use proper line breaks between stanzas or paragraphs, correct punctuation, and clear spacing.
    Return ONLY the content itself — no title, no label, no introduction or explanation.
    """

    payload = %{
      model: model,
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: "Write a #{style} about: #{prompt}"}
      ],
      stream: false,
      options: %{num_ctx: 2048}
    }

    case Req.post("#{ollama_url()}/api/chat", json: payload, receive_timeout: 90_000) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        send(pid, {:compose_ready, String.trim(content)})

      {:error, reason} ->
        send(pid, {:compose_error, inspect(reason)})

      other ->
        send(pid, {:compose_error, inspect(other)})
    end
  end

  defp transcribe_audio(base64_audio, mime_type) do
    audio_bytes = Base.decode64!(base64_audio)

    case Req.post("#{ai_service_url()}/transcribe",
           body: audio_bytes,
           headers: [{"content-type", mime_type}],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: %{"text" => text}}} -> {:ok, text}
      {:ok, resp} -> {:error, resp.status}
      {:error, reason} -> {:error, reason}
    end
  end
end
