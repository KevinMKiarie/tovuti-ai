defmodule TovutiAi.Repo do
  use Ecto.Repo,
    otp_app: :tovuti_ai,
    adapter: Ecto.Adapters.Postgres
end
