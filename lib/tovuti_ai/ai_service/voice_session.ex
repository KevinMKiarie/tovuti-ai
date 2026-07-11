defmodule TovutiAi.VoiceSession do
  use WebSockex
  require Logger

  @default_url "ws://localhost:8000/ws/voice"

  defp ws_url do
    base = Application.get_env(:tovuti_ai, :ai_service_url, "http://localhost:8000")
    String.replace(base, ~r/^http/, "ws") <> "/ws/voice"
  rescue
    _ -> @default_url
  end

  # Public API

  def start_link(caller_pid, opts \\ []) do
    WebSockex.start_link(ws_url(), __MODULE__, %{caller: caller_pid}, opts)
  end

  def send_audio(pid, base64_chunk) do
    WebSockex.cast(pid, {:send_audio, base64_chunk})
  end

  def interrupt(pid) do
    WebSockex.cast(pid, :interrupt)
  end

  def set_context(pid, messages, opts \\ []) do
    model = Keyword.get(opts, :model, "phi3:mini")
    voice = Keyword.get(opts, :voice, "af_heart")
    pace = Keyword.get(opts, :pace, 1.0)
    WebSockex.cast(pid, {:set_context, messages, model, voice, pace})
  end

  # WebSockex callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        handle_server_msg(decoded, state)

      {:error, reason} ->
        Logger.warning("VoiceSession: failed to decode message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:send_audio, b64}, state) do
    frame = Jason.encode!(%{"type" => "audio_chunk", "data" => b64})
    {:reply, {:text, frame}, state}
  end

  def handle_cast(:interrupt, state) do
    frame = Jason.encode!(%{"type" => "interrupt"})
    {:reply, {:text, frame}, state}
  end

  def handle_cast({:set_context, messages, model, voice, pace}, state) do
    frame =
      Jason.encode!(%{
        "type" => "context",
        "messages" => messages,
        "model" => model,
        "voice" => voice,
        "pace" => pace
      })

    {:reply, {:text, frame}, state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    Logger.warning("VoiceSession: disconnected: #{inspect(disconnect_map)}")
    send(state.caller, :voice_session_disconnected)
    {:ok, state}
  end

  @impl WebSockex
  def terminate(_reason, _state) do
    :ok
  end

  # Private helpers

  defp handle_server_msg(%{"type" => "transcript", "text" => text}, state) do
    send(state.caller, {:voice_transcript, text})
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "token", "text" => token}, state) do
    send(state.caller, {:voice_token, token})
    {:ok, state}
  end

  defp handle_server_msg(
         %{"type" => "audio_chunk", "seq" => seq, "data" => data},
         state
       ) do
    send(state.caller, {:voice_audio_chunk, seq, data})
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "done", "final_seq" => seq}, state) do
    send(state.caller, {:voice_done, seq})
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "done"}, state) do
    send(state.caller, {:voice_done, 0})
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "speech_start"}, state) do
    send(state.caller, :voice_speech_start)
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "processing"}, state) do
    send(state.caller, :voice_processing)
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "interrupt_ack"}, state) do
    send(state.caller, :voice_interrupt_ack)
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "pong"}, state) do
    {:ok, state}
  end

  defp handle_server_msg(%{"type" => "error", "message" => message}, state) do
    Logger.warning("VoiceSession: error from server: #{message}")
    {:ok, state}
  end

  defp handle_server_msg(_msg, state) do
    {:ok, state}
  end
end
