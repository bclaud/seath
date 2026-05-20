defmodule Seath.Workers.ApplyArchiveRules do
  @moduledoc """
  Oban cron worker that applies all enabled tag-based archival rules.

  Runs nightly via Oban.Cron. Iterates over enabled rules, transitions
  matching documents to the configured target status, and returns a
  summary of rules applied and documents archived.
  """
  use Oban.Worker, queue: :archive_cron, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    rules = Seath.ArchiveRules.list_enabled_rules()

    total =
      Enum.reduce(rules, 0, fn rule, acc ->
        acc + Seath.ArchiveRules.apply_rule(rule)
      end)

    {:ok, %{rules_applied: length(rules), documents_archived: total}}
  end
end
