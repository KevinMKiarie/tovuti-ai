defmodule TovutiAi.Conversations.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :role, :string
    field :content, :string
    field :audio_path, :string
    belongs_to :thread, TovutiAi.Conversations.Thread

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :audio_path, :thread_id])
    |> validate_required([:role, :content, :thread_id])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
