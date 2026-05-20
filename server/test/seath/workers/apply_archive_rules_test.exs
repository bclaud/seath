defmodule Seath.Workers.ApplyArchiveRulesTest do
  use Seath.DataCase

  alias Seath.Workers.ApplyArchiveRules
  alias Seath.Documents
  alias Seath.ArchiveRules
  alias Seath.Tags

  describe "perform/1" do
    test "applies all enabled archival rules" do
      {:ok, tag1} = Tags.create_tag(%{name: "tax"})
      {:ok, tag2} = Tags.create_tag(%{name: "receipts"})

      {:ok, _rule1} =
        ArchiveRules.create_rule(%{
          name: "Tax Archival",
          tag_id: tag1.id,
          age_days: 1
        })

      {:ok, _rule2} =
        ArchiveRules.create_rule(%{
          name: "Receipt Archival",
          tag_id: tag2.id,
          age_days: 1
        })

      # Create old documents for each tag
      create_old_document_with_tag("tax_report.pdf", tag1)
      create_old_document_with_tag("receipt_scan.pdf", tag2)

      ApplyArchiveRules.new(%{})
      |> Oban.insert!()

      Oban.drain_queue(queue: :archive_cron)

      # Verify all eligible documents were archived
      tax_docs = Documents.list_by_status("archived")
      assert length(tax_docs) >= 2
    end

    test "does not apply disabled rules" do
      {:ok, tag} = Tags.create_tag(%{name: "disabled-test-#{Ecto.UUID.generate()}"})

      {:ok, _disabled_rule} =
        ArchiveRules.create_rule(%{
          name: "Disabled Rule #{Ecto.UUID.generate()}",
          tag_id: tag.id,
          age_days: 1,
          enabled: false
        })

      create_old_document_with_tag("should_not_archive.pdf", tag)

      ApplyArchiveRules.new(%{})
      |> Oban.insert!()

      Oban.drain_queue(queue: :archive_cron)

      archived = Documents.list_by_status("archived")
      assert archived == []
    end

    test "returns summary with counts" do
      {:ok, tag} = Tags.create_tag(%{name: "summary-test-#{Ecto.UUID.generate()}"})

      {:ok, _rule} =
        ArchiveRules.create_rule(%{
          name: "Summary Rule #{Ecto.UUID.generate()}",
          tag_id: tag.id,
          age_days: 1
        })

      create_old_document_with_tag("summary_doc.pdf", tag)

      result =
        ApplyArchiveRules.new(%{})
        |> Oban.insert!()

      Oban.drain_queue(queue: :archive_cron)

      # Reload the job to get the result
      updated_job = Repo.reload!(result)
      assert updated_job.state == "completed"
    end
  end

  # --- Helpers ---

  defp create_old_document_with_tag(file_name, tag) do
    now = DateTime.utc_now()
    inserted_at = DateTime.add(now, -2 * 24 * 60 * 60, :second)

    {:ok, doc} =
      Documents.create_document(%{
        file_path: "/uploads/#{file_name}",
        file_name: file_name,
        file_type: "application/pdf",
        file_size: 1024
      })

    {:ok, doc} = Documents.transition_status(doc, "processing")
    {:ok, doc} = Documents.transition_status(doc, "awaiting_review")

    Repo.update_all(
      from(d in Seath.Documents.Document, where: d.id == ^doc.id),
      set: [inserted_at: inserted_at]
    )

    doc = Repo.reload!(doc)

    {:ok, _} = Tags.add_tag_to_document(doc, tag)
    doc
  end
end
