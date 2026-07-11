defmodule TovutiAi.Conversations.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "threads" do
    field :title, :string
    field :deleted_at, :utc_datetime
    belongs_to :user, TovutiAi.Accounts.User, type: :integer
    has_many :messages, TovutiAi.Conversations.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:title, :deleted_at, :user_id])
    |> validate_required([:user_id])
  end
end
