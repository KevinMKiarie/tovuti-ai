defmodule TovutiAiWeb.UserRegistrationHTML do
  use TovutiAiWeb, :html

  embed_templates "user_registration_html/*"

  defp local_mail_adapter? do
    Application.get_env(:tovuti_ai, TovutiAi.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
