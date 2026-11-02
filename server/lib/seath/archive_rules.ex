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
      |> Enum.filter(&jev_eligible_for_rule?(&1, rule))

    Enum.each(docs, fn doc ->
      Seath.Documents.transition_status(doc, rule.target_status)
    end)

    length(docs)
  end

  @doc """
  JEV-like System-1 discriminative gatekeeper for automatic archival.

  Evaluates whether a classified document is safe to archive without human intervention:
    1. `Score` — calibrated confidence must be >= `min_confidence` (default `0.85`)
    2. `Verification` — grounding verification must have `passed: true` with zero flagged fields
    3. `Noul (needs_human_review)` — model must not have flagged ambiguity (`needs_human_review != true`)
    4. `Noul (is_actionable)` — actionable documents (unpaid bills, deadlines) stay in Review unless overridden
  """
  def jev_gatekeeper_allows_auto_archive?(
        _doc,
        classification,
        verification,
        confidence,
        opts \\ []
      ) do
    min_confidence = Keyword.get(opts, :min_confidence, 0.85)
    allow_actionable = Keyword.get(opts, :allow_actionable, false)

    ver_passed =
      case verification do
        %{passed: p} -> p == true
        %{"passed" => p} -> p == true
        _ -> false
      end

    flagged =
      case verification do
        %{flagged_fields: f} when is_list(f) -> f
        %{"flagged_fields" => f} when is_list(f) -> f
        _ -> []
      end

    needs_review =
      Map.get(classification || %{}, :needs_human_review) == true or
        Map.get(classification || %{}, "needs_human_review") == true

    is_actionable =
      Map.get(classification || %{}, :is_actionable) == true or
        Map.get(classification || %{}, "is_actionable") == true

    is_number(confidence) and
      confidence >= min_confidence and
      ver_passed and
      flagged == [] and
      not needs_review and
      (allow_actionable or not is_actionable)
  end

  @doc """
  Checks whether a document stored in the database passes the JEV gatekeeper
  for scheduled archival rules.

  Documents that were explicitly flagged by verification (`passed == false`),
  have low confidence (`< 0.5`), or were marked `needs_human_review: true` in
  `llm_reasoning` are held back in `awaiting_review` for human inspection when
  the rule's target status is `"archived"`.
  """
  def jev_eligible_for_rule?(%Seath.Documents.Document{} = doc, %ArchivalRule{
        target_status: "archived"
      }) do
    ver_failed =
      is_map(doc.verification_data) and Map.get(doc.verification_data, "passed") == false

    low_confidence = is_number(doc.confidence) and doc.confidence < 0.5

    needs_review =
      case doc.llm_reasoning do
        bin when is_binary(bin) ->
          case Jason.decode(bin) do
            {:ok, %{"classification" => %{"needs_human_review" => true}}} -> true
            {:ok, %{"needs_human_review" => true}} -> true
            _ -> false
          end

        _ ->
          false
      end

    not ver_failed and not low_confidence and not needs_review
  end

  def jev_eligible_for_rule?(%Seath.Documents.Document{}, %ArchivalRule{}), do: true
end
