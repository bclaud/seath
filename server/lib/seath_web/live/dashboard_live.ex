defmodule SeathWeb.DashboardLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    pending_count = length(Seath.Documents.list_by_status("pending"))
    review_count = length(Seath.Documents.list_by_status("awaiting_review"))
    archived_count = length(Seath.Documents.list_by_status("archived"))
    recent_documents = Seath.Documents.list_recent_documents()

    {:ok,
     socket
     |> assign(:pending_count, pending_count)
     |> assign(:review_count, review_count)
     |> assign(:archived_count, archived_count)
     |> assign(:recent_documents, recent_documents)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:dashboard} review_count={@review_count}>
      <div class="p-8">
        <h2 class="text-2xl font-bold text-base-content mb-8">Dashboard</h2>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <a
            href="/upload"
            class="block bg-white rounded-xl border p-6 hover:shadow-md transition-shadow"
          >
            <div class="flex items-center justify-between mb-4">
              <.icon name="hero-clock" class="w-8 h-8 text-yellow-500" />
              <span class="text-3xl font-bold text-yellow-600">{@pending_count}</span>
            </div>
            <h3 class="text-sm font-medium text-base-content/80">Pending</h3>
          </a>
          <a
            href="/review"
            class="block bg-white rounded-xl border p-6 hover:shadow-md transition-shadow"
          >
            <div class="flex items-center justify-between mb-4">
              <.icon name="hero-check-badge" class="w-8 h-8 text-purple-500" />
              <span class="text-3xl font-bold text-purple-600">{@review_count}</span>
            </div>
            <h3 class="text-sm font-medium text-base-content/80">Awaiting Review</h3>
          </a>
          <a
            href="/documents"
            class="block bg-white rounded-xl border p-6 hover:shadow-md transition-shadow"
          >
            <div class="flex items-center justify-between mb-4">
              <.icon name="hero-archive-box" class="w-8 h-8 text-green-500" />
              <span class="text-3xl font-bold text-green-600">{@archived_count}</span>
            </div>
            <h3 class="text-sm font-medium text-base-content/80">Archived</h3>
          </a>
        </div>

        <%!-- Recent documents --%>
        <div :if={@recent_documents != []} class="bg-white rounded-xl border p-6 mb-8">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-base-content">Recent Documents</h3>
            <.link
              navigate={~p"/documents"}
              class="text-sm text-blue-600 hover:text-blue-800 font-medium"
            >
              View all →
            </.link>
          </div>
          <div class="divide-y divide-gray-100">
            <div
              :for={doc <- @recent_documents}
              class="flex items-center gap-4 py-3 first:pt-0 last:pb-0"
            >
              <.link
                navigate={~p"/documents/#{doc.id}"}
                class="flex items-center gap-3 flex-1 min-w-0"
              >
                <.icon name="hero-document" class="w-5 h-5 shrink-0 text-base-content/40" />
                <span class="text-sm font-medium text-base-content truncate">
                  {doc.title || doc.file_name}
                </span>
                <span class={[
                  "shrink-0 inline-block px-2 py-0.5 rounded-full text-xs font-medium",
                  status_badge_class(doc.status)
                ]}>
                  {doc.status}
                </span>
              </.link>
              <span class="text-xs text-base-content/40 shrink-0">
                {format_date(doc.inserted_at)}
              </span>
            </div>
          </div>
        </div>

        <div class="bg-white rounded-xl border p-6">
          <h3 class="text-lg font-semibold text-base-content mb-4">Quick Actions</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <a
              href="/upload"
              class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all"
            >
              <.icon name="hero-arrow-up-tray" class="w-8 h-8 shrink-0 text-base-content/90" />
              <div>
                <h4 class="text-sm font-medium text-base-content">Upload Documents</h4>
                <p class="text-xs text-base-content/80 mt-0.5">
                  Drop files to ingest, OCR, and classify
                </p>
              </div>
            </a>
            <a
              href="/review"
              class="flex items-center gap-4 p-4 rounded-lg border border-yellow-300 bg-yellow-50 hover:shadow-sm transition-all"
            >
              <.icon name="hero-check-badge" class="w-8 h-8 shrink-0 text-yellow-600" />
              <div>
                <h4 class="text-sm font-medium text-base-content">Review Classifications</h4>
                <p class="text-xs text-base-content/80 mt-0.5">
                  Approve or reject proposed document tags
                </p>
              </div>
            </a>
            <a
              href="/documents"
              class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all"
            >
              <.icon name="hero-document-text" class="w-8 h-8 shrink-0 text-base-content/90" />
              <div>
                <h4 class="text-sm font-medium text-base-content">Browse Documents</h4>
                <p class="text-xs text-base-content/80 mt-0.5">Search and view archived documents</p>
              </div>
            </a>
            <a
              href="/chat"
              class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all"
            >
              <.icon name="hero-chat-bubble-left-right" class="w-8 h-8 shrink-0 text-base-content/90" />
              <div>
                <h4 class="text-sm font-medium text-base-content">Chat with Documents</h4>
                <p class="text-xs text-base-content/80 mt-0.5">
                  Ask questions about archived documents
                </p>
              </div>
            </a>
            <a
              href="/dev/dashboard"
              class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all"
            >
              <.icon name="hero-cog-6-tooth" class="w-8 h-8 shrink-0 text-base-content/90" />
              <div>
                <h4 class="text-sm font-medium text-base-content">Admin Dashboard</h4>
                <p class="text-xs text-base-content/80 mt-0.5">
                  Oban queues, system metrics, mail preview
                </p>
              </div>
            </a>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
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

  defp format_date(nil), do: "—"

  defp format_date(dt) do
    dt |> DateTime.to_date() |> Date.to_string()
  end
end
