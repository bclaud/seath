defmodule Seath.Workers.ArchiveWorker do
  @moduledoc """
  Oban worker that archives a document.

  Transitions a document from `awaiting_review` to `archived` status.
  The `transition_status/2` function in `Seath.Documents` handles the
  state machine validation and sets `archived_at` automatically.
  """
  use Oban.Worker, queue: :archive, max_attempts: 3

  alias Seath.Documents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, doc} <- fetch_document(id),
         {:ok, archived_doc} <- Documents.transition_status(doc, "archived") do
      Phoenix.PubSub.broadcast(
        Seath.PubSub,
        "documents",
        {:document_updated, %{id: archived_doc.id, status: "archived"}}
      )

      Seath.Workers.EmbedWorker.new(%{"document_id" => archived_doc.id}) |> Oban.insert()
      :ok
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end
end
