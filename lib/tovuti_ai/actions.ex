defmodule TovutiAi.Actions do
  require Logger

  @tools [
    %{
      type: "function",
      function: %{
        name: "send_email",
        description: "Send an email via Gmail to a recipient",
        parameters: %{
          type: "object",
          properties: %{
            to: %{type: "string", description: "Recipient email address"},
            subject: %{type: "string", description: "Email subject line"},
            body: %{type: "string", description: "Email body text"}
          },
          required: ["to", "subject", "body"]
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "reschedule_meeting",
        description: "Reschedule a Cal.com meeting to a new time",
        parameters: %{
          type: "object",
          properties: %{
            booking_ref: %{
              type: "string",
              description: "Booking ID or reference (optional — uses next upcoming booking if omitted)"
            },
            new_start_time: %{
              type: "string",
              description: "New meeting start time in ISO 8601 format, e.g. 2026-07-01T14:00:00Z"
            },
            reason: %{type: "string", description: "Reason for rescheduling"}
          },
          required: ["new_start_time"]
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "send_whatsapp",
        description: "Send a WhatsApp message to one or more recipients. The 'phone' field accepts saved contact names (e.g. 'Mum', 'Samsung'), phone numbers with country code, or a comma-separated mix. If the user mentions a name, pass that name exactly as spoken — it will be resolved from the contacts list. NEVER fabricate or guess phone numbers.",
        parameters: %{
          type: "object",
          properties: %{
            phone: %{
              type: "string",
              description: "Contact name(s) or phone number(s). Examples: 'Mum' or '+254712345678' or 'Mum,Samsung'. Use the name as spoken — do NOT invent numbers."
            },
            message: %{type: "string", description: "Message text to send"}
          },
          required: ["phone", "message"]
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "compose_and_send",
        description: "Generate creative or research content (haiku, poem, essay, summary, news, story, research, etc.) and prepare it to send via WhatsApp. Use when the user asks to write something AND share/send it. Also use for 'create a haiku and send', 'write a poem for my contacts', etc.",
        parameters: %{
          type: "object",
          properties: %{
            style: %{type: "string", description: "Content type: 'haiku', 'poem', 'essay', 'research', 'summary', 'story', 'news', 'letter', etc."},
            prompt: %{type: "string", description: "What to write about — topic, subject, or instructions"},
            recipients: %{type: "string", description: "Contact name(s) or phone(s), comma-separated. Use 'all' to send to all saved contacts."}
          },
          required: ["style", "prompt", "recipients"]
        }
      }
    },
    %{
      type: "function",
      function: %{
        name: "create_booking",
        description: "Open the Cal.com booking page so the user can schedule a meeting, create a meeting link, or set up an appointment. Use when the user asks to book a call, create a meeting, or schedule time.",
        parameters: %{
          type: "object",
          properties: %{
            event_type: %{
              type: "string",
              description: "Optional Cal.com event type slug (e.g. '30min', '1hr'). Leave empty to show the default booking page."
            }
          },
          required: []
        }
      }
    }
  ]

  def tools, do: @tools

  def execute(%{"type" => type, "params" => params}) do
    url = Application.get_env(:tovuti_ai, :ai_service_url, "http://localhost:8000")

    Logger.info("[Actions] executing #{type}")

    case Req.post("#{url}#{endpoint(type)}", json: params, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: _status, body: %{"detail" => msg}}} ->
        {:error, msg}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def describe("send_email", params) do
    "Send an email to **#{params["to"]}** — subject: \"#{params["subject"]}\""
  end

  def describe("reschedule_meeting", params) do
    base = "Reschedule your meeting to **#{params["new_start_time"]}**"
    if params["reason"] && params["reason"] != "",
      do: base <> " (reason: #{params["reason"]})",
      else: base
  end

  def describe("send_whatsapp", params) do
    preview = String.slice(params["message"] || "", 0, 80)
    phones = params["phone"] || ""
    count = phones |> String.split(",") |> Enum.count(&(String.trim(&1) != ""))
    label = if count > 1, do: "#{count} recipients", else: phones
    "Send WhatsApp to **#{label}**: \"#{preview}\""
  end

  def describe("compose_and_send", params) do
    style = params["style"] || "content"
    prompt = params["prompt"] || ""
    recipients = params["recipients"] || ""
    "Generate a #{style} about \"#{prompt}\" and send to: #{recipients}"
  end

  def describe("create_booking", params) do
    case params["event_type"] do
      et when is_binary(et) and et != "" -> "Open Cal.com booking page (event: #{et})"
      _ -> "Open Cal.com booking page"
    end
  end

  def describe(type, _params), do: "Execute action: #{type}"

  def format_result("send_email", %{"status" => "sent", "to" => to, "subject" => subject}) do
    "Email sent to #{to} — \"#{subject}\""
  end

  def format_result("reschedule_meeting", _result), do: "Meeting rescheduled"

  def format_result("send_whatsapp", %{"status" => "sent", "count" => count, "recipients" => recipients}) do
    phones = recipients |> Enum.map(& &1["phone"]) |> Enum.join(", ")
    "WhatsApp message sent to #{count} recipient(s): #{phones}"
  end

  def format_result("send_whatsapp", %{"status" => "sent", "phone" => phone}) do
    "WhatsApp message sent to #{phone}"
  end

  def format_result(type, _result), do: "#{type} completed"

  defp endpoint("send_email"), do: "/actions/send_email"
  defp endpoint("reschedule_meeting"), do: "/actions/reschedule_meeting"
  defp endpoint("send_whatsapp"), do: "/actions/send_whatsapp"
end

