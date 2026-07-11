defmodule TovutiAi.VoiceClones.VoiceClone do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "voice_clones" do
    field :name, :string
    field :clip_path, :string
    belongs_to :user, TovutiAi.Accounts.User, type: :integer
    timestamps()
  end

  def changeset(voice, attrs) do
    voice
    |> cast(attrs, [:name, :clip_path, :user_id])
    |> validate_required([:name, :clip_path, :user_id])
    |> validate_length(:name, min: 1, max: 100)
  end
end
