defmodule SeathWeb.DocumentDetailLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    tags = Seath.Tags.list_tags()
    types = Seath.DocumentTypes.list_types()
    correspondents = Seath.Correspondents.list_correspondents()

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Seath.PubSub, "documents")
        socket
      else
        socket
      end

    {:ok,
     socket
     |> assign(:tags, tags)
     |> assign(:types, types)
     |> assign(:correspondents, correspondents)
     |> assign(:editing, false)
     |> assign(:edit_title, "")}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    doc =
      Seath.Documents.get_document!(id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    worker_jobs = Seath.WorkerJobs.latest_for_document(id)

    {:noreply,
     socket
     |> assign(:doc, doc)
     |> assign(:worker_jobs, worker_jobs)
     |> assign(:edit_title, doc.title || "")}
  end

  @impl true
  def handle_info({:document_updated, %{id: id}}, socket) do
    if socket.assigns.doc.id == id do
      doc =
        Seath.Documents.get_document!(id)
        |> Seath.Repo.preload([:tags, :document_type, :correspondent])

      worker_jobs = Seath.WorkerJobs.latest_for_document(id)

      {:noreply,
       socket
       |> assign(:doc, doc)
       |> assign(:worker_jobs, worker_jobs)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, false)}
  end

  @impl true
  def handle_event("save_metadata", %{"doc" => doc_params}, socket) do
    doc = socket.assigns.doc

    attrs = %{
      title: doc_params["title"],
      document_type_id: blank_to_nil(doc_params["document_type_id"]),
      correspondent_id: blank_to_nil(doc_params["correspondent_id"])
    }

    case Seath.Documents.update_document(doc, attrs) do
      {:ok, updated} ->
        updated = Seath.Repo.preload(updated, [:tags, :document_type, :correspondent])

        {:noreply,
         socket
         |> assign(:doc, updated)
         |> assign(:editing, false)
         |> put_flash(:info, "Document updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update document.")}
    end
  end

  @impl true
  def handle_event("retry_document", _params, socket) do
    {:ok, _updated} = Seath.Documents.retry_failed(socket.assigns.doc)

    doc =
      Seath.Documents.get_document!(socket.assigns.doc.id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    worker_jobs = Seath.WorkerJobs.latest_for_document(socket.assigns.doc.id)

    {:noreply,
     socket
     |> assign(:doc, doc)
     |> assign(:worker_jobs, worker_jobs)
     |> put_flash(:info, "Document queued for retry.")}
  end

  @impl true
  def handle_event("add_tag", %{"tag_id" => tag_id}, socket) do
    if tag_id != "" do
      doc = socket.assigns.doc
      tag = Seath.Tags.get_tag!(tag_id)
      Seath.Tags.add_tag_to_document(doc, tag)
    end

    updated =
      Seath.Documents.get_document!(socket.assigns.doc.id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    {:noreply, assign(socket, :doc, updated)}
  end

  @impl true
  def handle_event("remove_tag", %{"tag_id" => tag_id}, socket) do
    doc = socket.assigns.doc
    tag = Seath.Tags.get_tag!(tag_id)
    Seath.Tags.remove_tag_from_document(doc, tag)

    updated =
      Seath.Documents.get_document!(doc.id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    {:noreply, assign(socket, :doc, updated)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:documents}>
      <div class="max-w-5xl mx-auto py-8 px-6">
        <%!-- Breadcrumb --%>
        <nav class="flex items-center gap-2 text-sm text-base-content/60 mb-6">
          <.link navigate={~p"/documents"} class="hover:text-blue-600 transition-colors">
            <.icon name="hero-document-text" class="w-4 h-4 inline mr-1" /> Documents
          </.link>
          <.icon name="hero-chevron-right" class="w-3 h-3" />
          <span class="text-base-content/80 font-medium">{@doc.title || @doc.file_name}</span>
        </nav>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Main content --%>
          <div class="lg:col-span-2 space-y-6">
            <%!-- Metadata card --%>
            <div class="bg-white rounded-xl border p-6">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-lg font-semibold text-base-content">Document Info</h2>
                <button
                  :if={!@editing}
                  phx-click="start_edit"
                  class="text-sm text-blue-600 hover:text-blue-800 font-medium flex items-center gap-1"
                >
                  <.icon name="hero-pencil" class="w-4 h-4" /> Edit
                </button>
              </div>

              <%= if @editing do %>
                <form phx-submit="save_metadata" id="edit-metadata-form">
                  <div class="space-y-4">
                    <div>
                      <label class="block text-sm font-medium text-base-content/80 mb-1">Title</label>
                      <input
                        type="text"
                        name="doc[title]"
                        value={@edit_title}
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      />
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-base-content/80 mb-1">
                        Document Type
                      </label>
                      <select
                        name="doc[document_type_id]"
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      >
                        <option value="">None</option>
                        <option
                          :for={type <- @types}
                          value={type.id}
                          selected={@doc.document_type_id == type.id}
                        >
                          {type.name}
                        </option>
                      </select>
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-base-content/80 mb-1">
                        Correspondent
                      </label>
                      <select
                        name="doc[correspondent_id]"
                        class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                      >
                        <option value="">None</option>
                        <option
                          :for={c <- @correspondents}
                          value={c.id}
                          selected={@doc.correspondent_id == c.id}
                        >
                          {c.name}
                        </option>
                      </select>
                    </div>

                    <div class="flex gap-2 pt-2">
                      <button
                        type="submit"
                        class="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 transition-colors"
                      >
                        Save Changes
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_edit"
                        class="px-4 py-2 border border-gray-300 text-base-content/70 rounded-lg text-sm font-medium hover:bg-gray-50 transition-colors"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                </form>
              <% else %>
                <div class="grid grid-cols-2 gap-4">
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Title
                    </label>
                    <p class="text-base-content font-medium">{@doc.title || @doc.file_name}</p>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Status
                    </label>
                    <span class={[
                      "inline-block px-2.5 py-0.5 rounded-full text-xs font-medium",
                      status_badge_class(@doc.status)
                    ]}>
                      {@doc.status}
                    </span>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Document Type
                    </label>
                    <p class="text-base-content">
                      {(@doc.document_type && @doc.document_type.name) || "—"}
                    </p>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Correspondent
                    </label>
                    <p class="text-base-content">
                      {(@doc.correspondent && @doc.correspondent.name) || "—"}
                    </p>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      File Name
                    </label>
                    <p class="text-base-content/80 text-sm">{@doc.file_name}</p>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      File Size
                    </label>
                    <p class="text-base-content/80 text-sm">{format_file_size(@doc.file_size)}</p>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Created
                    </label>
                    <p class="text-base-content/80 text-sm">{format_datetime(@doc.inserted_at)}</p>
                  </div>
                  <div>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Last Updated
                    </label>
                    <p class="text-base-content/80 text-sm">{format_datetime(@doc.updated_at)}</p>
                  </div>
                  <div :if={@doc.archived_at}>
                    <label class="block text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Archived At
                    </label>
                    <p class="text-base-content/80 text-sm">{format_datetime(@doc.archived_at)}</p>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Tags section --%>
            <div class="bg-white rounded-xl border p-6">
              <h3 class="text-sm font-semibold text-base-content mb-3">Tags</h3>
              <div class="flex flex-wrap gap-2 mb-3">
                <span
                  :for={tag <- @doc.tags}
                  class="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 text-blue-900 rounded-full text-sm font-medium"
                >
                  {tag.name}
                  <button
                    phx-click="remove_tag"
                    phx-value-tag_id={tag.id}
                    class="ml-1 hover:text-blue-600"
                  >
                    <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                  </button>
                </span>
                <span :if={@doc.tags == []} class="text-sm text-base-content/40">No tags</span>
              </div>
              <form phx-change="add_tag" class="flex gap-2">
                <select name="tag_id" class="px-3 py-2 border border-gray-300 rounded-lg text-sm">
                  <option value="">Add tag...</option>
                  <option :for={tag <- @tags} value={tag.id}>{tag.name}</option>
                </select>
              </form>
            </div>

            <%!-- OCR Text --%>
            <div :if={@doc.ocr_text} class="bg-white rounded-xl border p-6">
              <h3 class="text-sm font-semibold text-base-content mb-3">Extracted Text</h3>
              <div class="bg-gray-50 rounded-lg p-4 max-h-96 overflow-y-auto">
                <pre class="text-sm text-base-content/90 whitespace-pre-wrap font-sans">{@doc.ocr_text}</pre>
              </div>
            </div>
          </div>

          <%!-- Sidebar --%>
          <div class="space-y-6">
            <%!-- Document preview --%>
            <div class="bg-white rounded-xl border p-4">
              <h3 class="text-sm font-semibold text-base-content mb-3">Preview</h3>
              <div class="bg-gray-50 rounded-lg overflow-hidden max-h-[700px]">
                <%= cond do %>
                  <% @doc.file_type == "application/pdf" -> %>
                    <object
                      data={"/documents/#{@doc.id}/file"}
                      type="application/pdf"
                      class="w-full min-h-[500px]"
                    >
                      <p class="p-4 text-sm text-base-content/60">
                        Your browser doesn't support embedded PDF viewing.
                        <a
                          href={"/documents/#{@doc.id}/download"}
                          class="text-blue-600 hover:text-blue-800 underline"
                        >
                          Download the PDF
                        </a>
                        to view it.
                      </p>
                    </object>
                  <% String.starts_with?(@doc.file_type, "image/") -> %>
                    <img
                      src={"/documents/#{@doc.id}/file"}
                      alt={"Preview of #{@doc.title || @doc.file_name}"}
                      class="w-full h-auto object-contain"
                      loading="lazy"
                    />
                  <% true -> %>
                    <div class="flex items-center justify-center min-h-[200px]">
                      <p class="text-sm text-base-content/40">
                        Preview not available for this file type.
                      </p>
                    </div>
                <% end %>
              </div>
            </div>

            <%!-- Confidence --%>
            <div :if={@doc.confidence} class="bg-white rounded-xl border p-6">
              <h3 class="text-sm font-semibold text-base-content mb-3">Confidence</h3>
              <div class="flex items-center gap-3">
                <div class="flex-1 bg-gray-200 rounded-full h-3">
                  <div
                    class={[
                      "h-3 rounded-full transition-all",
                      cond do
                        @doc.confidence >= 0.8 -> "bg-green-500"
                        @doc.confidence >= 0.5 -> "bg-yellow-500"
                        true -> "bg-red-500"
                      end
                    ]}
                    style={"width: #{Float.round(@doc.confidence * 100)}%"}
                  >
                  </div>
                </div>
                <span class={[
                  "text-sm font-medium",
                  cond do
                    @doc.confidence >= 0.8 -> "text-green-700"
                    @doc.confidence >= 0.5 -> "text-yellow-700"
                    true -> "text-red-700"
                  end
                ]}>
                  {Float.round(@doc.confidence * 100, 1)}%
                </span>
              </div>
            </div>

            <%!-- Pipeline Status --%>
            <div
              :if={@worker_jobs[:ocr] != [] or @worker_jobs[:classify] != []}
              class="bg-white rounded-xl border p-4"
            >
              <h3 class="text-sm font-semibold text-base-content mb-3">Pipeline Status</h3>
              <div class="space-y-2">
                <div :for={job <- @worker_jobs[:ocr]}>
                  <div class="flex items-center justify-between text-xs">
                    <span class="font-medium text-base-content/70">OCR</span>
                    <span class={["px-2 py-0.5 rounded-full font-medium", job_state_class(job.state)]}>
                      {job.state}
                      <%= if job.attempt > 0 do %>
                        ({job.attempt}/{job.max_attempts})
                      <% end %>
                    </span>
                  </div>
                  <p :if={job.error} class="text-xs text-red-600 mt-0.5 font-mono">{job.error}</p>
                </div>
                <div :for={job <- @worker_jobs[:classify]}>
                  <div class="flex items-center justify-between text-xs">
                    <span class="font-medium text-base-content/70">Classification</span>
                    <span class={["px-2 py-0.5 rounded-full font-medium", job_state_class(job.state)]}>
                      {job.state}
                      <%= if job.attempt > 0 do %>
                        ({job.attempt}/{job.max_attempts})
                      <% end %>
                    </span>
                  </div>
                  <p :if={job.error} class="text-xs text-red-600 mt-0.5 font-mono">{job.error}</p>
                </div>
              </div>
            </div>

            <%!-- Actions --%>
            <div class="bg-white rounded-xl border p-6">
              <h3 class="text-sm font-semibold text-base-content mb-3">Actions</h3>
              <div class="space-y-2">
                <button
                  :if={@doc.status == "error"}
                  phx-click="retry_document"
                  class="flex items-center gap-2 w-full px-4 py-2.5 bg-red-600 text-white rounded-lg text-sm font-medium hover:bg-red-700 transition-colors"
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4" /> Retry Processing
                </button>

                <a
                  href={"/documents/#{@doc.id}/download"}
                  class="flex items-center gap-2 w-full px-4 py-2.5 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 transition-colors"
                >
                  <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Download Original
                </a>

                <a
                  href={"/documents/#{@doc.id}/file"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center gap-2 w-full px-4 py-2.5 border border-gray-300 text-base-content/80 rounded-lg text-sm font-medium hover:bg-gray-50 transition-colors"
                >
                  <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" /> Open Original
                </a>

                <.link
                  navigate={~p"/review"}
                  class="flex items-center gap-2 w-full px-4 py-2.5 border border-gray-300 text-base-content/80 rounded-lg text-sm font-medium hover:bg-gray-50 transition-colors"
                >
                  <.icon name="hero-check-badge" class="w-4 h-4" /> Review Classification
                </.link>
              </div>
            </div>

            <%!-- File info --%>
            <div class="bg-white rounded-xl border p-6">
              <h3 class="text-sm font-semibold text-base-content mb-3">File Details</h3>
              <dl class="space-y-2 text-sm">
                <div class="flex justify-between">
                  <dt class="text-base-content/60">Type</dt>
                  <dd class="text-base-content">{@doc.file_type}</dd>
                </div>
                <div class="flex justify-between">
                  <dt class="text-base-content/60">Size</dt>
                  <dd class="text-base-content">{format_file_size(@doc.file_size)}</dd>
                </div>
                <div :if={@doc.ocr_text} class="flex justify-between">
                  <dt class="text-base-content/60">Text Length</dt>
                  <dd class="text-base-content">{String.length(@doc.ocr_text)} chars</dd>
                </div>
              </dl>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val

  defp job_state_class(state) do
    case state do
      "completed" -> "bg-green-100 text-green-700"
      "executing" -> "bg-blue-100 text-blue-700"
      "available" -> "bg-yellow-100 text-yellow-700"
      "discarded" -> "bg-red-100 text-red-700"
      "retrying" -> "bg-orange-100 text-orange-700"
      "retryable" -> "bg-orange-100 text-orange-700"
      "cancelled" -> "bg-gray-100 text-gray-500"
      _ -> "bg-gray-100 text-gray-600"
    end
  end

  defp status_badge_class(status) do
    case status do
      "pending" -> "bg-yellow-100 text-yellow-800"
      "processing" -> "bg-blue-100 text-blue-800"
      "awaiting_review" -> "bg-purple-100 text-purple-800"
      "archived" -> "bg-green-100 text-green-800"
      "rejected" -> "bg-red-100 text-red-800"
      "error" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{div(bytes, 1024)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_datetime(nil), do: "—"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
  end
end
