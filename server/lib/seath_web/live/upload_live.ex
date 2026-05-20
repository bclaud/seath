defmodule SeathWeb.UploadLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Seath.PubSub, "documents")
    end

    {:ok,
     socket
     |> allow_upload(:document,
       accept: ~w(.pdf .png .jpg .jpeg .tiff .txt),
       max_entries: 10,
       max_file_size: 50_000_000
     )
      |> assign(:uploaded_docs, [])}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_docs =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        case Seath.Documents.ingest(path, entry.client_name) do
          {:ok, doc} -> {:ok, doc}
          {:error, _reason} -> {:error, entry.client_name}
        end
      end)

    successful = Enum.filter(uploaded_docs, &match?({:ok, _}, &1))
    failed = Enum.filter(uploaded_docs, &match?({:error, _}, &1))

    socket =
      socket
      |> assign(:uploaded_docs, successful ++ socket.assigns.uploaded_docs)
      |> put_flash(:info, "#{length(successful)} document(s) uploaded successfully")

    socket =
      if failed != [] do
        put_flash(socket, :error, "#{length(failed)} document(s) failed to upload")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:document_updated, updated}, socket) do
    updated_docs =
      Enum.map(socket.assigns.uploaded_docs, fn
        {:ok, doc} when doc.id == updated.id ->
          {:ok, Map.put(doc, :status, to_string(updated.status))}
        other ->
          other
      end)

    {:noreply, assign(socket, :uploaded_docs, updated_docs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:upload}>
      <div class="max-w-2xl mx-auto py-12 px-4">
        <h1 class="text-2xl font-bold mb-8">Upload Documents</h1>

        <%!-- Upload zone --%>
        <label
          id="upload-zone"
          phx-drop-target={@uploads.document.ref}
          class={[
            "block border-2 border-dashed border-gray-300 rounded-xl p-12 text-center cursor-pointer",
            "hover:border-blue-400 hover:bg-blue-50 transition-colors",
            length(@uploads.document.entries) > 0 && "border-blue-400 bg-blue-50"
          ]}
        >
          <.live_file_input
            upload={@uploads.document}
            class="hidden"
          />
          <.icon name="hero-arrow-up-tray" class="w-12 h-12 mx-auto text-gray-400 mb-4" />
          <p class="text-gray-600 mb-2">Drag and drop files here, or click to browse</p>
          <p class="text-sm text-gray-400">PDF, PNG, JPG, TIFF, TXT — up to 50MB each</p>
        </label>

        <%!-- Upload progress --%>
        <div :for={entry <- @uploads.document.entries} class="mt-4 p-4 bg-white rounded-lg border">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium text-gray-700">{entry.client_name}</span>
            <span class="text-sm text-gray-500">{entry.progress}%</span>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div
              class="bg-blue-500 h-2 rounded-full transition-all"
              style={"width: #{entry.progress}%"}
            >
            </div>
          </div>
          <p :if={entry.valid? == false} class="text-sm text-red-500 mt-2">
            {upload_errors(@uploads.document, entry) |> Enum.map(&to_string/1) |> Enum.join(", ")}
          </p>
        </div>

        <%!-- Upload button --%>
        <button
          :if={length(@uploads.document.entries) > 0}
          phx-click="save"
          class="mt-6 w-full bg-blue-600 text-white py-3 px-6 rounded-lg font-medium
                 hover:bg-blue-700 transition-colors disabled:opacity-50"
        >
          Upload {length(@uploads.document.entries)} file(s)
        </button>

        <%!-- Uploaded documents --%>
        <div :if={@uploaded_docs != []} class="mt-8">
          <h2 class="text-lg font-semibold mb-4">Uploaded Documents</h2>
          <div class="space-y-2">
            <div
              :for={{_id, doc} <- @uploaded_docs}
              class="p-3 bg-green-50 border border-green-200 rounded-lg"
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-document-check" class="w-5 h-5 text-green-600" />
                <span class="text-sm font-medium text-green-800">{doc.file_name}</span>
                <span class={[
                  "text-xs px-2 py-0.5 rounded-full font-medium",
                  case doc.status do
                    "pending" -> "bg-yellow-100 text-yellow-800"
                    "processing" -> "bg-blue-100 text-blue-800"
                    "awaiting_review" -> "bg-purple-100 text-purple-800"
                    "archived" -> "bg-green-100 text-green-800"
                    "rejected" -> "bg-red-100 text-red-800"
                    _ -> "bg-gray-100 text-gray-800"
                  end
                ]}>
                  {doc.status}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
