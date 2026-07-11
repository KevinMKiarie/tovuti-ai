defmodule TovutiAi.VoiceClones do
  import Ecto.Query

  alias TovutiAi.Repo
  alias TovutiAi.Accounts.Scope
  alias TovutiAi.VoiceClones.VoiceClone

  def list_voices(%Scope{user: %{id: user_id}}) do
    Repo.all(from v in VoiceClone, where: v.user_id == ^user_id, order_by: [asc: v.inserted_at])
  end

  def get_voice!(%Scope{user: %{id: user_id}}, id) do
    Repo.get_by!(VoiceClone, id: id, user_id: user_id)
  end

  def create_voice(%Scope{user: %{id: user_id}}, attrs) do
    %VoiceClone{}
    |> VoiceClone.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  def delete_voice(%VoiceClone{} = voice), do: Repo.delete(voice)
end
