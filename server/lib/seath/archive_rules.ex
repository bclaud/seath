defmodule Seath.ArchiveRules do
  @moduledoc """
  The ArchiveRules context.

  Provides CRUD operations for tag-based archival rules, a preview
  function to see how many documents a rule would affect, and an
  apply function to execute a rule.
  """

  import Ecto.Query, warn: false
  alias Seath.Repo
  alias Seath.ArchiveRules.ArchivalRule

  @doc """
  Returns the list of all archival rules (with preloaded tags).
  """
  def list_rules do
    ArchivalRule
    |> Repo.all()
    |> Repo.preload(:tag)
  end

  @doc """
  Returns the list of enabled archival rules (with preloaded tags).
  """
  def list_enabled_rules do
    from(r in ArchivalRule, where: r.enabled == true)
    |> Repo.all()
    |> Repo.preload(:tag)
  end

  @doc """
  Gets a single archival rule by id.

  Raises `Ecto.NoResultsError` if the rule does not exist.
  """
  def get_rule!(id), do: Repo.get!(ArchivalRule, id) |> Repo.preload(:tag)

  @doc """
  Creates a new archival rule.
  """
  def create_rule(attrs) do
    %ArchivalRule{}
    |> ArchivalRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing archival rule.
  """
  def update_rule(%ArchivalRule{} = rule, attrs) do
    rule
    |> ArchivalRule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an archival rule.
  """
  def delete_rule(%ArchivalRule{} = rule) do
    Repo.delete(rule)
  end

  @doc """
  Previews how many documents would be affected by applying a rule.

  Returns the count of documents that match the rule's tag, are older
  than the configured age, and are not already in the target status
  or rejected.
  """
  def preview_rule(%ArchivalRule{} = rule) do
    cutoff = DateTime.utc_now() |> DateTime.add(-rule.age_days * 24 * 60 * 60, :second)

    from(d in Seath.Documents.Document,
      join: dt in "document_tags",
      on: dt.document_id == d.id,
      where: dt.tag_id == type(^rule.tag_id, :binary_id),
      where: d.inserted_at < ^cutoff,
      where: d.status not in ^[rule.target_status, "rejected"],
      select: count(d.id)
    )
    |> Repo.one()
  end

  @doc """
  Applies an archival rule, transitioning matching documents to the
  target status.

  Returns the number of documents that were transitioned.
  """
  def apply_rule(%ArchivalRule{} = rule) do
    cutoff = DateTime.utc_now() |> DateTime.add(-rule.age_days * 24 * 60 * 60, :second)

    docs =
      from(d in Seath.Documents.Document,
        join: dt in "document_tags",
        on: dt.document_id == d.id,
        where: dt.tag_id == type(^rule.tag_id, :binary_id),
        where: d.inserted_at < ^cutoff,
        where: d.status not in ^[rule.target_status, "rejected"],
        select: d
      )
      |> Repo.all()

    Enum.each(docs, fn doc ->
      Seath.Documents.transition_status(doc, rule.target_status)
    end)

    length(docs)
  end
end
