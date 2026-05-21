defmodule SeathWeb.DashboardLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    pending_count = length(Seath.Documents.list_by_status("pending"))
    review_count = length(Seath.Documents.list_by_status("awaiting_review"))
    archived_count = length(Seath.Documents.list_by_status("archived"))

    {:ok,
     socket
     |> assign(:pending_count, pending_count)
     |> assign(:review_count, review_count)
     |> assign(:archived_count, archived_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:dashboard} review_count={@review_count}>
      <div class="p-8">
        <h2 class="text-2xl font-bold text-gray-900 mb-8">Dashboard</h2>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <a href="/upload" class="block bg-white rounded-xl border p-6 hover:shadow-md transition-shadow">
            <div class="flex items-center justify-between mb-4">
              <.icon name="hero-clock" class="w-8 h-8 text-yellow-500" />
              <span class="text-3xl font-bold text-yellow-600">{@pending_count}</span>
            </div>
            <h3 class="text-sm font-medium text-gray-700">Pending</h3>
          </a>
          <a href="/review" class="block bg-white rounded-xl border p-6 hover:shadow-md transition-shadow">
            <div class="flex items-center justify-between mb-4">
              <.icon name="hero-check-badge" class="w-8 h-8 text-purple-500" />
              <span class="text-3xl font-bold text-purple-600">{@review_count}</span>
            </div>
            <h3 class="text-sm font-medium text-gray-700">Awaiting Review</h3>
          </a>
          <a href="#" class="block bg-white rounded-xl border p-6 hover:shadow-md transition-shadow">
            <div class="flex items-center justify-between mb-4">
              <.icon name="hero-archive-box" class="w-8 h-8 text-green-500" />
              <span class="text-3xl font-bold text-green-600">{@archived_count}</span>
            </div>
            <h3 class="text-sm font-medium text-gray-700">Archived</h3>
          </a>
        </div>

        <div class="bg-white rounded-xl border p-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-4">Quick Actions</h3>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <a href="/upload" class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all">
              <.icon name="hero-arrow-up-tray" class="w-8 h-8 shrink-0 text-gray-500" />
              <div>
                <h4 class="text-sm font-medium text-gray-900">Upload Documents</h4>
                <p class="text-xs text-gray-700 mt-0.5">Drop files to ingest, OCR, and classify</p>
              </div>
            </a>
            <a href="/review" class="flex items-center gap-4 p-4 rounded-lg border border-yellow-300 bg-yellow-50 hover:shadow-sm transition-all">
              <.icon name="hero-check-badge" class="w-8 h-8 shrink-0 text-yellow-600" />
              <div>
                <h4 class="text-sm font-medium text-gray-900">Review Classifications</h4>
                <p class="text-xs text-gray-700 mt-0.5">Approve or reject proposed document tags</p>
              </div>
            </a>
            <a href="/chat" class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all">
              <.icon name="hero-chat-bubble-left-right" class="w-8 h-8 shrink-0 text-gray-500" />
              <div>
                <h4 class="text-sm font-medium text-gray-900">Chat with Documents</h4>
                <p class="text-xs text-gray-700 mt-0.5">Ask questions about archived documents</p>
              </div>
            </a>
            <a href="/dev/dashboard" class="flex items-center gap-4 p-4 rounded-lg border border-gray-200 hover:border-gray-300 hover:shadow-sm transition-all">
              <.icon name="hero-cog-6-tooth" class="w-8 h-8 shrink-0 text-gray-500" />
              <div>
                <h4 class="text-sm font-medium text-gray-900">Admin Dashboard</h4>
                <p class="text-xs text-gray-700 mt-0.5">Oban queues, system metrics, mail preview</p>
              </div>
            </a>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
