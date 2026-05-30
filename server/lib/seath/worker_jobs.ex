defmodule Seath.WorkerJobs do
  @moduledoc """
  Queries Oban jobs related to documents for status transparency.

  Uses Ecto to query the oban_jobs table directly, filtering by args->>document_id.
  """

  import Ecto.Query
  alias Seath.Repo

  # Workers that process documents
  @document_workers [
    "Seath.Workers.OCRWorker",
    "Seath.Workers.ClassifyWorker"
  ]

  @doc """
  Returns the most recent Oban jobs for a given document, grouped by worker type.

  Accepts a document id as a binary string or an integer.

  Returns a map: `%{ocr: [job], classify: [job]}` where each list contains
  `Oban.Job` structs ordered by most recently inserted first (up to 20 total).
  """
  def latest_for_document(document_id) when is_binary(document_id) do
    query =
      from j in Oban.Job,
        where: fragment("args->>'document_id' = ?", ^document_id),
        where: j.worker in ^@document_workers,
        order_by: [desc: j.inserted_at],
        limit: 20

    jobs = Repo.all(query)

    %{
      ocr: Enum.filter(jobs, &(&1.worker == "Seath.Workers.OCRWorker")),
      classify: Enum.filter(jobs, &(&1.worker == "Seath.Workers.ClassifyWorker"))
    }
  end

  def latest_for_document(document_id) when is_integer(document_id) do
    latest_for_document(Integer.to_string(document_id))
  end
end
