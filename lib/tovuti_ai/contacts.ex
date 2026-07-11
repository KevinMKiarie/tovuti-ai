defmodule TovutiAi.Contacts do
  import Ecto.Query
  alias TovutiAi.Repo
  alias TovutiAi.Contacts.Contact

  def list(user_id) do
    Repo.all(from c in Contact, where: c.user_id == ^user_id, order_by: c.name)
  end

  def create(user_id, attrs) do
    %Contact{user_id: user_id}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end

  def delete(user_id, id) do
    case Repo.get_by(Contact, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      contact -> Repo.delete(contact)
    end
  end

  # Resolve a comma-separated string of names/numbers to phone numbers.
  # Values that already look like numbers are passed through unchanged.
  # Names are looked up case-insensitively against the contacts table.
  # Returns {:ok, resolved_phones_string} | {:error, unresolved_names}
  def resolve_recipients(user_id, phones_or_names) do
    entries =
      phones_or_names
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    contacts = list(user_id)
    contact_map = Map.new(contacts, fn c -> {String.downcase(c.name), c.phone} end)

    {resolved, unresolved} =
      Enum.reduce(entries, {[], []}, fn entry, {ok, err} ->
        if looks_like_number?(entry) do
          {ok ++ [entry], err}
        else
          case Map.get(contact_map, String.downcase(entry)) do
            nil -> {ok, err ++ [entry]}
            phone -> {ok ++ [phone], err}
          end
        end
      end)

    if unresolved == [] do
      {:ok, Enum.join(resolved, ",")}
    else
      {:error, unresolved, resolved}
    end
  end

  defp looks_like_number?(str) do
    String.match?(str, ~r/^\+?[\d\s\-\(\)]+$/)
  end
end
