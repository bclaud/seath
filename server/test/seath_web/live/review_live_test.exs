defmodule SeathWeb.ReviewLiveTest do
  use SeathWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders review page with empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/review")
    assert html =~ "Document Review"
    assert html =~ "No documents awaiting review"
  end

  test "shows documents awaiting review", %{conn: conn} do
    _doc =
      Seath.Documents.create_document(%{
        file_path: "/tmp/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "awaiting_review",
        title: "Test Invoice",
        ocr_text: "Invoice #12345"
      })

    {:ok, _view, html} = live(conn, ~p"/review")
    assert html =~ "Test Invoice"
    assert html =~ "1 document(s) awaiting review"
  end

  test "can select a document and see details", %{conn: conn} do
    {:ok, doc} =
      Seath.Documents.create_document(%{
        file_path: "/tmp/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "awaiting_review",
        title: "Test Invoice",
        ocr_text: "Invoice #12345"
      })

    {:ok, view, _html} = live(conn, ~p"/review")

    # Select the document
    view
    |> element("#doc-list-item-#{doc.id} div", "Test Invoice")
    |> render_click()

    html = render(view)
    assert html =~ "Approve &amp; Archive"
    assert html =~ "Reject"
    assert html =~ "Invoice #12345"
  end

  test "can approve a document", %{conn: conn} do
    {:ok, doc} =
      Seath.Documents.create_document(%{
        file_path: "/tmp/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "awaiting_review",
        title: "Test Invoice"
      })

    {:ok, view, _html} = live(conn, ~p"/review")

    # Select the document
    view
    |> element("#doc-list-item-#{doc.id} div", "Test Invoice")
    |> render_click()

    assert render(view) =~ "Approve &amp; Archive"

    # Approve it
    view
    |> element("#approve-btn")
    |> render_click()

    # Verify it's archived
    updated = Seath.Documents.get_document!(doc.id)
    assert updated.status == "archived"
  end

  test "can reject a document", %{conn: conn} do
    {:ok, doc} =
      Seath.Documents.create_document(%{
        file_path: "/tmp/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "awaiting_review",
        title: "Test Invoice"
      })

    {:ok, view, _html} = live(conn, ~p"/review")

    view
    |> element("#doc-list-item-#{doc.id} div", "Test Invoice")
    |> render_click()

    view
    |> element("#reject-btn")
    |> render_click()

    updated = Seath.Documents.get_document!(doc.id)
    assert updated.status == "rejected"
  end

  test "shows empty state after approving last document", %{conn: conn} do
    {:ok, doc} =
      Seath.Documents.create_document(%{
        file_path: "/tmp/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "awaiting_review",
        title: "Test Invoice"
      })

    {:ok, view, _html} = live(conn, ~p"/review")

    view
    |> element("#doc-list-item-#{doc.id} div", "Test Invoice")
    |> render_click()

    view
    |> element("#approve-btn")
    |> render_click()

    html = render(view)
    assert html =~ "No documents awaiting review"
  end

  test "can reclassify a document", %{conn: conn} do
    {:ok, doc} =
      Seath.Documents.create_document(%{
        file_path: "/tmp/test.pdf",
        file_name: "test.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "awaiting_review",
        title: "Test Invoice",
        confidence: 0.45,
        llm_reasoning: "Initial classification",
        verification_data: %{
          "passed" => false,
          "flagged_fields" => ["correspondent"],
          "verified_fields" => ["title"]
        },
        classification_attempts: 1
      })

    {:ok, view, _html} = live(conn, ~p"/review")

    # Select the document
    view
    |> element("#doc-list-item-#{doc.id} div", "Test Invoice")
    |> render_click()

    assert render(view) =~ "Reclassify"

    # Click reclassify
    view
    |> element("#reclassify-btn")
    |> render_click()

    # Verify the document is now in processing status
    updated = Seath.Documents.get_document!(doc.id)
    assert updated.status == "processing"
    assert updated.llm_reasoning == nil
    assert updated.verification_data == %{}
    assert updated.classification_attempts == 0
  end
end
