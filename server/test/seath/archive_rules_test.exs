defmodule Seath.ArchiveRulesTest do
  use Seath.DataCase

  alias Seath.ArchiveRules
  alias Seath.ArchiveRules.ArchivalRule
  alias Seath.Tags
  alias Seath.Documents

  @doc_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "create_rule/1" do
    test "creates a rule with valid attrs" do
      {:ok, tag} = Tags.create_tag(%{name: "tax"})

      assert {:ok, %ArchivalRule{} = rule} =
               ArchiveRules.create_rule(%{
                 name: "Archive Tax Docs",
                 tag_id: tag.id,
                 age_days: 90,
                 target_status: "archived",
                 enabled: true
               })

      assert rule.name == "Archive Tax Docs"
      assert rule.tag_id == tag.id
      assert rule.age_days == 90
      assert rule.target_status == "archived"
      assert rule.enabled == true
    end

    test "creates a rule with default values" do
      {:ok, tag} = Tags.create_tag(%{name: "receipts"})

      assert {:ok, %ArchivalRule{} = rule} =
               ArchiveRules.create_rule(%{
                 name: "Receipt Archival",
                 tag_id: tag.id,
                 age_days: 90
               })

      assert rule.age_days == 90
      assert rule.target_status == "archived"
      assert rule.enabled == true
    end

    test "returns error when name is missing" do
      {:ok, tag} = Tags.create_tag(%{name: "invoices"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               ArchiveRules.create_rule(%{tag_id: tag.id, age_days: 30})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error when tag_id is missing" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               ArchiveRules.create_rule(%{name: "No Tag Rule", age_days: 30})

      assert "can't be blank" in errors_on(changeset).tag_id
    end

    test "defaults age_days to 90 when not provided" do
      {:ok, tag} = Tags.create_tag(%{name: "contracts"})

      assert {:ok, %ArchivalRule{} = rule} =
               ArchiveRules.create_rule(%{name: "Contracts Archival", tag_id: tag.id})

      assert rule.age_days == 90
    end

    test "returns error when age_days is zero" do
      {:ok, tag} = Tags.create_tag(%{name: "urgent"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               ArchiveRules.create_rule(%{
                 name: "Urgent Archival",
                 tag_id: tag.id,
                 age_days: 0
               })

      assert "must be greater than 0" in errors_on(changeset).age_days
    end

    test "returns error when age_days is negative" do
      {:ok, tag} = Tags.create_tag(%{name: "old"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               ArchiveRules.create_rule(%{
                 name: "Old Docs",
                 tag_id: tag.id,
                 age_days: -1
               })

      assert "must be greater than 0" in errors_on(changeset).age_days
    end

    test "returns error when target_status is invalid" do
      {:ok, tag} = Tags.create_tag(%{name: "bills"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               ArchiveRules.create_rule(%{
                 name: "Bills Archival",
                 tag_id: tag.id,
                 age_days: 30,
                 target_status: "pending"
               })

      assert "is invalid" in errors_on(changeset).target_status
    end

    test "returns error when name is not unique" do
      {:ok, tag} = Tags.create_tag(%{name: "finance"})

      assert {:ok, _rule} =
               ArchiveRules.create_rule(%{
                 name: "Finance Archival",
                 tag_id: tag.id,
                 age_days: 60
               })

      assert {:error, %Ecto.Changeset{} = changeset} =
               ArchiveRules.create_rule(%{
                 name: "Finance Archival",
                 tag_id: tag.id,
                 age_days: 30
               })

      assert errors_on(changeset).name
    end
  end

  describe "list_rules/0" do
    test "returns all rules" do
      {:ok, tag} = Tags.create_tag(%{name: "tax"})
      {:ok, r1} = ArchiveRules.create_rule(%{name: "Rule A", tag_id: tag.id, age_days: 30})
      {:ok, r2} = ArchiveRules.create_rule(%{name: "Rule B", tag_id: tag.id, age_days: 60})

      rules = ArchiveRules.list_rules()
      assert length(rules) == 2
      assert Enum.any?(rules, &(&1.id == r1.id))
      assert Enum.any?(rules, &(&1.id == r2.id))
    end

    test "returns empty list when no rules exist" do
      assert ArchiveRules.list_rules() == []
    end

    test "preloads the tag association" do
      {:ok, tag} = Tags.create_tag(%{name: "receipts"})

      {:ok, _rule} =
        ArchiveRules.create_rule(%{name: "Receipts Rule", tag_id: tag.id, age_days: 30})

      [rule] = ArchiveRules.list_rules()
      assert rule.tag.id == tag.id
      assert rule.tag.name == "receipts"
    end
  end

  describe "list_enabled_rules/0" do
    test "returns only enabled rules" do
      {:ok, tag} = Tags.create_tag(%{name: "filter"})
      {:ok, _r1} = ArchiveRules.create_rule(%{name: "Enabled Rule", tag_id: tag.id, age_days: 30})

      {:ok, _r2} =
        ArchiveRules.create_rule(%{
          name: "Disabled Rule",
          tag_id: tag.id,
          age_days: 60,
          enabled: false
        })

      rules = ArchiveRules.list_enabled_rules()
      assert length(rules) == 1
      assert hd(rules).name == "Enabled Rule"
    end
  end

  describe "get_rule!/1" do
    test "returns the rule with the given id" do
      {:ok, tag} = Tags.create_tag(%{name: "single"})
      {:ok, rule} = ArchiveRules.create_rule(%{name: "Single Rule", tag_id: tag.id, age_days: 30})

      fetched = ArchiveRules.get_rule!(rule.id)
      assert fetched.id == rule.id
      assert fetched.tag.id == tag.id
    end

    test "raises when rule does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        ArchiveRules.get_rule!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_rule/2" do
    setup :create_tag_and_rule

    test "updates rule attributes", %{rule: rule} do
      assert {:ok, updated} =
               ArchiveRules.update_rule(rule, %{name: "Updated Name", age_days: 45})

      assert updated.name == "Updated Name"
      assert updated.age_days == 45
    end

    test "returns error with invalid data", %{rule: rule} do
      assert {:error, %Ecto.Changeset{}} = ArchiveRules.update_rule(rule, %{age_days: -5})
    end
  end

  describe "delete_rule/1" do
    setup :create_tag_and_rule

    test "deletes the rule", %{rule: rule} do
      assert {:ok, %ArchivalRule{}} = ArchiveRules.delete_rule(rule)
      assert_raise Ecto.NoResultsError, fn -> ArchiveRules.get_rule!(rule.id) end
    end
  end

  describe "preview_rule/1" do
    setup :prepare_documents_for_rule

    test "returns count of documents that match the rule", %{rule: rule, old_doc: old_doc} do
      # used in setup
      _ = old_doc
      assert ArchiveRules.preview_rule(rule) == 1
    end

    test "returns 0 when no documents match" do
      {:ok, fresh_tag} = Tags.create_tag(%{name: "empty-preview-#{Ecto.UUID.generate()}"})

      {:ok, rule} =
        ArchiveRules.create_rule(%{
          name: "Empty Preview Rule",
          tag_id: fresh_tag.id,
          age_days: 1
        })

      assert ArchiveRules.preview_rule(rule) == 0
    end
  end

  describe "apply_rule/1" do
    setup :prepare_documents_for_rule

    test "transitions matching documents to target status", %{
      rule: rule,
      old_doc: old_doc,
      tag: _tag
    } do
      assert ArchiveRules.apply_rule(rule) == 1

      updated = Documents.get_document!(old_doc.id)
      assert updated.status == "archived"
    end

    test "does not affect documents that already have target status", %{
      rule: rule,
      tag: tag
    } do
      {:ok, already_archived} =
        Documents.create_document(Map.put(@doc_attrs, :file_name, "archived.pdf"))

      # Transition through the state machine to get to awaiting_review, then archived
      {:ok, already_archived} = Documents.transition_status(already_archived, "processing")
      {:ok, already_archived} = Documents.transition_status(already_archived, "awaiting_review")
      {:ok, already_archived} = Documents.transition_status(already_archived, "archived")
      {:ok, _} = Tags.add_tag_to_document(already_archived, tag)

      # only the old_doc, not the already_archived one
      assert ArchiveRules.apply_rule(rule) == 1

      archived_doc = Documents.get_document!(already_archived.id)
      assert archived_doc.status == "archived"
    end

    test "does not transition recently-created documents", %{rule: rule, tag: tag} do
      {:ok, recent_doc} =
        Documents.create_document(Map.put(@doc_attrs, :file_name, "recent.pdf"))

      {:ok, recent_doc} = Documents.transition_status(recent_doc, "processing")
      {:ok, _recent_doc} = Documents.transition_status(recent_doc, "awaiting_review")
      {:ok, _} = Tags.add_tag_to_document(recent_doc, tag)

      # only the old_doc
      assert ArchiveRules.apply_rule(rule) == 1
    end
  end

  # --- Helpers ---

  defp create_tag_and_rule(_context) do
    {:ok, tag} = Tags.create_tag(%{name: "test-tag-#{Ecto.UUID.generate()}"})

    {:ok, rule} =
      ArchiveRules.create_rule(%{
        name: "Test Rule #{Ecto.UUID.generate()}",
        tag_id: tag.id,
        age_days: 30
      })

    %{tag: tag, rule: rule}
  end

  defp prepare_documents_for_rule(_context) do
    {:ok, tag} = Tags.create_tag(%{name: "archive-me-#{Ecto.UUID.generate()}"})

    {:ok, rule} =
      ArchiveRules.create_rule(%{
        name: "Archive Old Docs #{Ecto.UUID.generate()}",
        tag_id: tag.id,
        age_days: 1,
        target_status: "archived"
      })

    # Create an old document (set inserted_at to 2 days ago)
    old_doc = create_document_with_age("old_doc.pdf", tag, -2)

    # Create a recent document (inserted_at = now, should not be affected by 1-day rule)
    {:ok, recent_doc} =
      Documents.create_document(Map.put(@doc_attrs, :file_name, "recent.pdf"))

    {:ok, recent_doc} = Documents.transition_status(recent_doc, "processing")
    {:ok, _recent_doc} = Documents.transition_status(recent_doc, "awaiting_review")
    {:ok, _} = Tags.add_tag_to_document(recent_doc, tag)

    %{tag: tag, rule: rule, old_doc: old_doc}
  end

  defp create_document_with_age(file_name, tag, days_offset) do
    now = DateTime.utc_now()
    inserted_at = DateTime.add(now, days_offset * 24 * 60 * 60, :second)

    {:ok, doc} =
      Documents.create_document(%{
        file_path: "/uploads/#{file_name}",
        file_name: file_name,
        file_type: "application/pdf",
        file_size: 1024
      })

    # Manually set inserted_at by directly updating the database
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
