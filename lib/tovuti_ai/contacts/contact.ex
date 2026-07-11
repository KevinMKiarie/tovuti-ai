defmodule TovutiAi.Contacts.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contacts" do
    field :name, :string
    field :phone, :string
    belongs_to :user, TovutiAi.Accounts.User
    timestamps()
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:name, :phone])
    |> validate_required([:name, :phone])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_format(:phone, ~r/^\+?[\d\s\-\(\)]+$/, message: "must be a valid phone number")
    |> update_change(:phone, &normalize_phone/1)
  end

  defp normalize_phone(phone) do
    phone
    |> String.replace(~r/[\s\-\(\)]/, "")
    |> then(fn p -> if String.starts_with?(p, "+"), do: p, else: "+" <> p end)
  end
end
