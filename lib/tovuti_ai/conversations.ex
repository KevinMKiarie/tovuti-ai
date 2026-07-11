defmodule TovutiAi.Conversations do
  import Ecto.Query

  alias TovutiAi.Repo
  alias TovutiAi.Accounts.Scope
  alias TovutiAi.Conversations.{Message, Thread}

  def list_threads(%Scope{user: %{id: user_id}}) do
    Thread
    |> where([t], t.user_id == ^user_id and is_nil(t.deleted_at))
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def soft_delete_thread(%Scope{user: %{id: user_id}}, id) do
    case Repo.get_by(Thread, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      thread ->
        thread
        |> Thread.changeset(%{deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()
    end
  end

  def get_thread_with_messages(%Scope{user: %{id: user_id}}, id) do
    messages_query = from(m in Message, order_by: [asc: m.inserted_at])

    thread =
      Thread
      |> where([t], t.id == ^id and t.user_id == ^user_id and is_nil(t.deleted_at))
      |> Repo.one()

    case thread do
      nil -> nil
      thread -> Repo.preload(thread, messages: messages_query)
    end
  end

  def create_thread(%Scope{user: %{id: user_id}}, attrs \\ %{}) do
    %Thread{}
    |> Thread.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def delete_messages(ids) when is_list(ids) do
    Repo.delete_all(from m in Message, where: m.id in ^ids)
    :ok
  end
end
