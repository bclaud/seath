defmodule SeathWeb.UploadLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Seath.PubSub, "documents")
    end

    pending = Seath.Documents.list_by_status("pending")
    processing = Seath.Documents.list_by_status("processing")
    errored = Seath.Documents.list_by_status("error")
    ocr_configured? = not is_nil(Seath.OCR.impl())
    llm_configured? = not is_nil(Seath.LLM.impl())

    {:ok,
     socket
     |> allow_upload(:document,
       accept: ~w(.pdf .png .jpg .jpeg .tiff .txt),
       max_entries: 10,
       max_file_size: 50_000_000
     )
     |> assign(:in_flight, pending ++ processing ++ errored)
     |> assign(:ocr_configured, ocr_configured?)
     |> assign(:llm_configured, llm_configured?)}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    File.mkdir_p!(Seath.Storage.upload_dir())

    docs =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        case Seath.Documents.ingest(path, entry.client_name) do
          {:ok, doc} ->
            Seath.Workers.OCRWorker.new(%{"document_id" => doc.id}) |> Oban.insert()
            {:ok, doc}

          {:error, reason} ->
            {:ok, %{error: reason, name: entry.client_name}}
        end
      end)

    successes = Enum.filter(docs, &is_struct(&1, Seath.Documents.Document))
    errors = Enum.reject(docs, &is_struct(&1, Seath.Documents.Document))

    {:noreply,
     socket
     |> assign(:in_flight, successes ++ socket.assigns.in_flight)
     |> put_flash(:info, "#{length(successes)} document(s) uploaded — pipeline started")
     |> then(fn s ->
       if errors != [], do: put_flash(s, :error, "#{length(errors)} document(s) failed"),
       else: s
     end)}
  end

  @impl true
  def handle_event("retry", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, _retried} = Seath.Documents.retry(doc)

    # Re-enqueue the appropriate worker based on the document's state
    Seath.Workers.OCRWorker.new(%{"document_id" => doc.id}) |> Oban.insert()

    # Update in_flight list
    in_flight =
      Enum.map(socket.assigns.in_flight, fn
        %{id: d_id} = d when d_id == id -> %{d | status: "pending", error_message: nil}
        other -> other
      end)

    Phoenix.PubSub.broadcast(
      Seath.PubSub,
      "documents",
      {:document_updated, %{id: doc.id, status: "pending"}}
    )

    {:noreply, assign(socket, :in_flight, in_flight) |> put_flash(:info, "Document queued for retry")}
  end

  @impl true
  def handle_info({:document_updated, updated}, socket) do
    in_flight =
      Enum.map(socket.assigns.in_flight, fn
        %{id: id} = doc when id == updated.id ->
          %{doc | status: to_string(updated.status)}
        other ->
          other
      end)

    {:noreply, assign(socket, :in_flight, in_flight)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:upload}>
      <div class="max-w-4xl mx-auto py-8 px-4">
        <h1 class="text-2xl font-bold text-gray-900 mb-2">Upload Documents</h1>
        <p class="text-gray-800 mb-8">Files are automatically OCR'd, classified, and sent to review</p>
        <%!-- Config warnings --%>

        <%!-- Config warnings --%>
        <div :if={!@ocr_configured} class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg flex items-center gap-3">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-yellow-600 shrink-0" />
          <p class="text-sm text-yellow-800">
            No OCR provider configured.
            <a href="/settings" class="underline font-medium hover:text-yellow-900">Go to Settings</a> to enable document processing.
          </p>
        </div>
        <div :if={!@llm_configured} class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg flex items-center gap-3">
          <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-yellow-600 shrink-0" />
          <p class="text-sm text-yellow-800">
            No LLM provider configured.
            <a href="/settings" class="underline font-medium hover:text-yellow-900">Go to Settings</a> to enable classification and chat.
          </p>
        </div>

        <form id="upload-form" phx-change="validate" phx-submit="save">
          <div
            id="upload-zone"
            phx-drop-target={@uploads.document.ref}
            phx-hook="UploadZone"
            class={[
              "border-2 border-dashed border-gray-300 rounded-xl p-12 text-center cursor-pointer",
              "hover:border-blue-400 hover:bg-blue-50 transition-colors",
              length(@uploads.document.entries) > 0 && "border-blue-400 bg-blue-50"
            ]}
          >
            <.live_file_input upload={@uploads.document} />
            <.icon name="hero-arrow-up-tray" class="w-12 h-12 mx-auto text-gray-800 mb-4" />
            <p class="text-gray-800 mb-2">Drag and drop files here, or click to browse</p>
            <p class="text-sm text-gray-800">PDF, PNG, JPG, TIFF, TXT — up to 50MB each</p>
          </div>

          <div :for={entry <- @uploads.document.entries} class="mt-4 p-4 bg-white rounded-lg border">
            <div class="flex items-center justify-between mb-2">
              <span class="text-sm font-medium text-gray-700">{entry.client_name}</span>
              <span class="text-sm text-gray-800">{entry.progress}%</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-2">
              <div class="bg-blue-500 h-2 rounded-full transition-all" style={"width: #{entry.progress}%"}>
              </div>
            </div>
            <p :if={entry.valid? == false} class="text-sm text-red-500 mt-2">
              {upload_errors(@uploads.document, entry) |> Enum.map(&to_string/1) |> Enum.join(", ")}
            </p>
          </div>

          <button
            :if={length(@uploads.document.entries) > 0}
            type="submit"
            class="mt-6 w-full bg-blue-600 text-white py-3 px-6 rounded-lg font-medium hover:bg-blue-700 transition-colors"
          >
            Upload {length(@uploads.document.entries)} file(s)
          </button>
        </form>

        <%!-- Pipeline status --%>
        <div :if={@in_flight != []} class="mt-8">
          <h2 class="text-lg font-semibold mb-2">Pipeline Status</h2>
          <p class="text-sm text-gray-800 mb-4">
            <span class="text-yellow-600">{count_by_status(@in_flight, "pending")}</span> pending ·
            <span class="text-blue-600">{count_by_status(@in_flight, "processing")}</span> processing ·
            <span class="text-red-600">{count_by_status(@in_flight, "error")}</span> failed
          </p>
          <div class="space-y-3">
            <div :for={doc <- @in_flight} class={[
              "p-4 bg-white rounded-lg border",
              doc.status == "error" && "border-red-200",
              doc.status == "pending" && "border-yellow-200",
              doc.status == "processing" && "border-blue-200"
            ]}>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3 min-w-0">
                  <.icon name="hero-document-text" class="w-5 h-5 shrink-0 text-gray-800" />
                  <span class="text-sm font-medium text-gray-900 truncate">{doc.title || doc.file_name}</span>
                </div>
                <.status_badge status={doc.status} />
              </div>

              <div :if={doc.status != "error"} class="mt-3">
                <.pipeline_bar status={doc.status} />
              </div>

              <div :if={doc.status == "error"} class="mt-3 p-3 bg-red-50 rounded-lg border border-red-100">
                <p class="text-xs text-red-700 font-mono whitespace-pre-wrap">{doc.error_message}</p>
                <button
                  phx-click="retry"
                  phx-value-id={doc.id}
                  class="mt-2 px-3 py-1.5 bg-red-600 text-white text-xs rounded-lg font-medium hover:bg-red-700 transition-colors"
                >
                  Retry
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp count_by_status(docs, status) do
    Enum.count(docs, &(&1.status == status))
  end

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full font-medium",
      @status == "pending" && "bg-yellow-50 text-yellow-700 border border-yellow-200",
      @status == "processing" && "bg-blue-50 text-blue-700 border border-blue-200 animate-pulse",
      @status == "awaiting_review" && "bg-purple-50 text-purple-700 border border-purple-200",
      @status == "archived" && "bg-green-50 text-green-700 border border-green-200",
      @status == "rejected" && "bg-red-50 text-red-700 border border-red-200",
      @status == "error" && "bg-red-50 text-red-700 border border-red-200"
    ]}>
      <span :if={@status == "processing"} class="w-1.5 h-1.5 bg-blue-500 rounded-full animate-ping" />
      {@status}
    </span>
    """
  end

  attr :status, :string, required: true

  def pipeline_bar(assigns) do
    assigns = assign(assigns, :rank, status_rank(assigns.status))

    ~H"""
    <div class="flex items-center gap-0 w-full">
      <div class={["flex-1 h-1.5 rounded-l-full", bar_color(0, @rank)]} />
      <div class={["flex-1 h-1.5", bar_color(1, @rank)]} />
      <div class={["flex-1 h-1.5", bar_color(2, @rank)]} />
      <div class={["flex-1 h-1.5 rounded-r-full", bar_color(3, @rank)]} />
    </div>
    <div class="flex justify-between mt-1 text-[10px]">
      <span class={step_text(0, @rank)}>Uploaded</span>
      <span class={step_text(1, @rank)}>OCR</span>
      <span class={step_text(2, @rank)}>Classify</span>
      <span class={step_text(3, @rank)}>Review</span>
    </div>
    """
  end

  defp bar_color(idx, rank) when idx < rank, do: "bg-green-500"
  defp bar_color(idx, rank) when idx == rank, do: "bg-blue-500"
  defp bar_color(_idx, _rank), do: "bg-gray-200"

  defp step_text(idx, rank) when idx < rank, do: "text-green-600"
  defp step_text(idx, rank) when idx == rank, do: "text-blue-600 font-semibold"
  defp step_text(_idx, _rank), do: "text-gray-800"

  defp status_rank("pending"), do: 0
  defp status_rank("processing"), do: 1
  defp status_rank("awaiting_review"), do: 2
  defp status_rank("archived"), do: 3
  defp status_rank(_), do: 0
end
