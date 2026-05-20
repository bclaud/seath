defmodule SeathWeb.ReviewLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    documents = Seath.Documents.list_by_status("awaiting_review")
    tags = Seath.Tags.list_tags()
    types = Seath.DocumentTypes.list_types()

    {:ok,
     socket
     |> assign(:documents, documents)
     |> assign(:tags, tags)
     |> assign(:types, types)
     |> assign(:selected_doc, nil)}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    doc =
      Seath.Documents.get_document!(id) |> Seath.Repo.preload([:tags, :document_type])

    {:noreply, assign(socket, :selected_doc, doc)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, _doc} = Seath.Documents.transition_status(doc, "archived")

    documents = Seath.Documents.list_by_status("awaiting_review")

    {:noreply,
     socket
     |> assign(:documents, documents)
     |> assign(:selected_doc, nil)
     |> put_flash(:info, "Document approved and archived.")}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, _doc} = Seath.Documents.transition_status(doc, "rejected")

    documents = Seath.Documents.list_by_status("awaiting_review")

    {:noreply,
     socket
     |> assign(:documents, documents)
     |> assign(:selected_doc, nil)
     |> put_flash(:info, "Document rejected.")}
  end

  @impl true
  def handle_event("update_title", %{"id" => id, "title" => title}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, updated} = Seath.Documents.update_document(doc, %{title: title})
    updated = Seath.Repo.preload(updated, [:tags, :document_type])
    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def handle_event("add_tag", %{"id" => id, "tag_id" => tag_id}, socket) do
    if tag_id != "" do
      doc = Seath.Documents.get_document!(id)
      tag = Seath.Tags.get_tag!(tag_id)
      Seath.Tags.add_tag_to_document(doc, tag)
    end

    updated =
      Seath.Documents.get_document!(id) |> Seath.Repo.preload([:tags, :document_type])

    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def handle_event("remove_tag", %{"id" => id, "tag_id" => tag_id}, socket) do
    doc = Seath.Documents.get_document!(id)
    tag = Seath.Tags.get_tag!(tag_id)
    Seath.Tags.remove_tag_from_document(doc, tag)

    updated =
      Seath.Documents.get_document!(id) |> Seath.Repo.preload([:tags, :document_type])

    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto py-8 px-4">
        <h1 class="text-2xl font-bold mb-2">Document Review</h1>
        <p class="text-gray-500 mb-8">
          {length(@documents)} document(s) awaiting review
        </p>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Document list --%>
          <div class="lg:col-span-1 space-y-2">
            <div
              :for={doc <- @documents}
              id={"doc-list-item-#{doc.id}"}
              phx-click="select"
              phx-value-id={doc.id}
              class={[
                "p-4 rounded-lg border cursor-pointer transition-colors",
                if(@selected_doc && @selected_doc.id == doc.id,
                  do: "border-blue-500 bg-blue-50",
                  else: "border-gray-200 hover:border-gray-300 bg-white"
                )
              ]}
            >
              <h3 class="font-medium text-gray-900 truncate">{doc.title || doc.file_name}</h3>
              <p class="text-sm text-gray-500 mt-1">
                {doc.file_type} · {format_file_size(doc.file_size)}
              </p>
            </div>

            <div :if={@documents == []} class="text-center py-12 text-gray-400">
              <.icon name="hero-inbox" class="w-12 h-12 mx-auto mb-3" />
              <p>No documents awaiting review</p>
            </div>
          </div>

          <%!-- Document detail --%>
          <div :if={@selected_doc} class="lg:col-span-2">
            <div class="bg-white rounded-xl border p-6">
              <%!-- Title --%>
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-1">Title</label>
                <form phx-change="update_title" phx-value-id={@selected_doc.id}>
                  <input
                    type="text"
                    name="title"
                    value={@selected_doc.title}
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  />
                </form>
              </div>

              <%!-- Document type --%>
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-1">Document Type</label>
                <p class="text-gray-900">
                  {if @selected_doc.document_type, do: @selected_doc.document_type.name, else: "None"}
                </p>
              </div>

              <%!-- Tags --%>
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-2">Tags</label>
                <div class="flex flex-wrap gap-2 mb-3">
                  <span
                    :for={tag <- @selected_doc.tags}
                    class="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm"
                  >
                    {tag.name}
                    <button
                      phx-click="remove_tag"
                      phx-value-id={@selected_doc.id}
                      phx-value-tag_id={tag.id}
                      class="ml-1 hover:text-blue-600"
                    >
                      <.icon name="hero-x-mark" class="w-4 h-4" />
                    </button>
                  </span>
                </div>
                <form phx-change="add_tag" phx-value-id={@selected_doc.id} class="flex gap-2">
                  <select name="tag_id" class="px-3 py-2 border border-gray-300 rounded-lg text-sm">
                    <option value="">Add tag...</option>
                    <option :for={tag <- @tags} value={tag.id}>{tag.name}</option>
                  </select>
                </form>
              </div>

              <%!-- OCR Text preview --%>
              <div class="mb-6">
                <label class="block text-sm font-medium text-gray-700 mb-1">Extracted Text</label>
                <div class="bg-gray-50 rounded-lg p-4 max-h-48 overflow-y-auto">
                  <p class="text-sm text-gray-600 whitespace-pre-wrap">
                    {if @selected_doc.ocr_text, do: String.slice(@selected_doc.ocr_text, 0, 1000), else: "No text extracted"}
                  </p>
                </div>
              </div>

              <%!-- Actions --%>
              <div class="flex gap-3 pt-4 border-t">
                <button
                  id="approve-btn"
                  phx-click="approve"
                  phx-value-id={@selected_doc.id}
                  class="flex-1 bg-green-600 text-white py-3 px-6 rounded-lg font-medium hover:bg-green-700 transition-colors"
                >
                  <.icon name="hero-check" class="w-5 h-5 inline mr-1" />
                  Approve &amp; Archive
                </button>
                <button
                  id="reject-btn"
                  phx-click="reject"
                  phx-value-id={@selected_doc.id}
                  class="flex-1 bg-red-600 text-white py-3 px-6 rounded-lg font-medium hover:bg-red-700 transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5 inline mr-1" />
                  Reject
                </button>
              </div>
            </div>
          </div>

          <%!-- Empty state --%>
          <div :if={!@selected_doc} class="lg:col-span-2 flex items-center justify-center">
            <div class="text-center text-gray-400">
              <.icon name="hero-document-magnifying-glass" class="w-16 h-16 mx-auto mb-4" />
              <p class="text-lg">Select a document to review</p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{div(bytes, 1024)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
