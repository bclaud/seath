defmodule SeathWeb.DocumentIndexLive do
  use SeathWeb, :live_view

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    tags = Seath.Tags.list_tags()
    types = Seath.DocumentTypes.list_types()
    correspondents = Seath.Correspondents.list_correspondents()

    {:ok,
     socket
     |> assign(:tags, tags)
     |> assign(:types, types)
     |> assign(:correspondents, correspondents)
     |> assign(:sidebar_open, false)
     |> assign(:total_count, 0)
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, :desc)
     |> assign(:search, "")
     |> assign(:filters, %{})
     |> stream(:documents, [], reset: true)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = max(1, String.to_integer(params["page"] || "1"))
    sort_by = params["sort_by"] || "inserted_at"
    sort_order = parse_sort_order(params["sort_order"])
    search = params["search"] || ""

    filters = %{
      status: params["status"] || "",
      tag_ids: parse_list_param(params["tag_ids"]),
      document_type_id: params["document_type_id"] || "",
      correspondent_id: params["correspondent_id"] || "",
      date_from: params["date_from"] || "",
      date_to: params["date_to"] || ""
    }

    opts = [
      page: page,
      per_page: @per_page,
      sort_by: sort_by,
      sort_order: sort_order,
      search: search,
      status: blank_to_nil(filters.status),
      tag_ids: empty_list_to_nil(filters.tag_ids),
      document_type_id: blank_to_nil(filters.document_type_id),
      correspondent_id: blank_to_nil(filters.correspondent_id),
      date_from: blank_to_nil(filters.date_from),
      date_to: blank_to_nil(filters.date_to)
    ]

    {documents, total_count} = Seath.Documents.list_documents_paginated(opts)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:search, search)
     |> assign(:filters, filters)
     |> assign(:total_count, total_count)
     |> assign(:pages, total_pages(total_count, @per_page))
     |> assign(:no_results, documents == [])
     |> stream(:documents, documents, reset: true)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/documents?#{build_query(socket, socket.assigns.filters, 1, search: search)}"
     )}
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    current_sort = socket.assigns.sort_by
    current_order = socket.assigns.sort_order

    {new_sort_by, new_sort_order} =
      if current_sort == field do
        {field, if(current_order == :asc, do: :desc, else: :asc)}
      else
        {field, :asc}
      end

    {:noreply,
     push_patch(socket,
       to:
         ~p"/documents?#{build_query(socket, socket.assigns.filters, 1,
         sort_by: new_sort_by,
         sort_order: new_sort_order)}"
     )}
  end

  @impl true
  def handle_event("page", %{"page" => page_str}, socket) do
    page = max(1, String.to_integer(page_str))
    total_pages = socket.assigns.pages
    page = min(page, total_pages)

    {:noreply,
     push_patch(socket, to: ~p"/documents?#{build_query(socket, socket.assigns.filters, page)}")}
  end

  @impl true
  def handle_event("apply_filters", filters_params, socket) do
    filters = %{
      status: filters_params["status"] || "",
      tag_ids: filters_params["tag_ids"] || [],
      document_type_id: filters_params["document_type_id"] || "",
      correspondent_id: filters_params["correspondent_id"] || "",
      date_from: filters_params["date_from"] || "",
      date_to: filters_params["date_to"] || ""
    }

    {:noreply, push_patch(socket, to: ~p"/documents?#{build_query(socket, filters, 1)}")}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/documents")}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:documents}>
      <div class="flex h-full">
        <%!-- Filter sidebar --%>
        <div
          id="filter-sidebar"
          class={[
            "w-72 bg-white border-r border-gray-200 overflow-y-auto shrink-0 transition-all duration-200",
            @sidebar_open && "max-w-72 opacity-100",
            !@sidebar_open && "max-w-0 opacity-0 overflow-hidden border-r-0"
          ]}
        >
          <div class="p-4">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-sm font-semibold text-base-content">Filters</h3>
              <button
                phx-click="clear_filters"
                class="text-xs text-blue-600 hover:text-blue-800 font-medium"
              >
                Clear all
              </button>
            </div>

            <form phx-change="apply_filters" id="filter-form">
              <%!-- Status --%>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Status
                </label>
                <select
                  name="status"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="">All statuses</option>
                  <option value="pending" selected={@filters.status == "pending"}>Pending</option>
                  <option value="processing" selected={@filters.status == "processing"}>
                    Processing
                  </option>
                  <option value="awaiting_review" selected={@filters.status == "awaiting_review"}>
                    Awaiting Review
                  </option>
                  <option value="archived" selected={@filters.status == "archived"}>Archived</option>
                  <option value="rejected" selected={@filters.status == "rejected"}>Rejected</option>
                  <option value="error" selected={@filters.status == "error"}>Error</option>
                </select>
              </div>

              <%!-- Tags --%>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Tags
                </label>
                <div class="space-y-1.5 max-h-40 overflow-y-auto">
                  <div :for={tag <- @tags} class="flex items-center gap-2">
                    <input
                      type="checkbox"
                      name="tag_ids[]"
                      value={tag.id}
                      checked={tag.id in @filters.tag_ids}
                      class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span class="text-sm text-base-content/90">{tag.name}</span>
                  </div>
                </div>
              </div>

              <%!-- Document Type --%>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Document Type
                </label>
                <select
                  name="document_type_id"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="">All types</option>
                  <option
                    :for={type <- @types}
                    value={type.id}
                    selected={@filters.document_type_id == type.id}
                  >
                    {type.name}
                  </option>
                </select>
              </div>

              <%!-- Correspondent --%>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Correspondent
                </label>
                <select
                  name="correspondent_id"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="">All correspondents</option>
                  <option
                    :for={correspondent <- @correspondents}
                    value={correspondent.id}
                    selected={@filters.correspondent_id == correspondent.id}
                  >
                    {correspondent.name}
                  </option>
                </select>
              </div>

              <%!-- Date range --%>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Date From
                </label>
                <input
                  type="date"
                  name="date_from"
                  value={@filters.date_from}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Date To
                </label>
                <input
                  type="date"
                  name="date_to"
                  value={@filters.date_to}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </form>
          </div>
        </div>

        <%!-- Main content --%>
        <div class="flex-1 overflow-y-auto">
          <div class="py-6 px-6">
            <%!-- Header row: toggle + search --%>
            <div class="flex items-center gap-4 mb-6">
              <button
                phx-click="toggle_sidebar"
                class="p-2 rounded-lg border border-gray-200 hover:bg-gray-50 transition-colors"
                title="Toggle filters"
              >
                <.icon name="hero-funnel" class="w-5 h-5 text-base-content/70" />
              </button>

              <h1 class="text-xl font-bold text-base-content">Documents</h1>

              <div class="flex-1 max-w-md ml-auto">
                <form phx-change="search" id="search-form">
                  <div class="relative">
                    <.icon
                      name="hero-magnifying-glass"
                      class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40"
                    />
                    <input
                      type="text"
                      name="search"
                      value={@search}
                      placeholder="Search documents..."
                      phx-debounce="300"
                      class="w-full pl-9 pr-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    />
                  </div>
                </form>
              </div>
            </div>

            <%!-- Document count --%>
            <div class="mb-4 text-sm text-base-content/70">
              {format_count(@total_count, @page, @per_page)}
            </div>

            <%!-- Table --%>
            <div class="bg-white rounded-xl border overflow-hidden">
              <table class="w-full">
                <thead>
                  <tr class="border-b bg-gray-50">
                    <th
                      phx-click="sort"
                      phx-value-field="title"
                      class="group px-4 py-3 text-left text-xs font-semibold text-base-content/70 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                    >
                      Title <.sort_icon active={@sort_by == "title"} order={@sort_order} />
                    </th>
                    <th
                      phx-click="sort"
                      phx-value-field="document_type_id"
                      class="group px-4 py-3 text-left text-xs font-semibold text-base-content/70 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                    >
                      Type <.sort_icon active={@sort_by == "document_type_id"} order={@sort_order} />
                    </th>
                    <th
                      phx-click="sort"
                      phx-value-field="correspondent_id"
                      class="group px-4 py-3 text-left text-xs font-semibold text-base-content/70 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                    >
                      Correspondent
                      <.sort_icon active={@sort_by == "correspondent_id"} order={@sort_order} />
                    </th>
                    <th class="px-4 py-3 text-left text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                      Tags
                    </th>
                    <th
                      phx-click="sort"
                      phx-value-field="inserted_at"
                      class="group px-4 py-3 text-left text-xs font-semibold text-base-content/70 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                    >
                      Created <.sort_icon active={@sort_by == "inserted_at"} order={@sort_order} />
                    </th>
                    <th
                      phx-click="sort"
                      phx-value-field="status"
                      class="group px-4 py-3 text-left text-xs font-semibold text-base-content/70 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                    >
                      Status <.sort_icon active={@sort_by == "status"} order={@sort_order} />
                    </th>
                    <th class="px-4 py-3 text-right text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody id="documents-list" phx-update="stream" class="divide-y divide-gray-100">
                  <tr :if={@no_results}>
                    <td colspan="7" class="px-4 py-12 text-center">
                      <.icon
                        name="hero-document-magnifying-glass"
                        class="w-12 h-12 mx-auto mb-3 text-base-content/40"
                      />
                      <p class="text-base-content font-medium">No documents found</p>
                      <p class="text-sm text-base-content/60 mt-1">
                        Try adjusting your search or filters
                      </p>
                    </td>
                  </tr>
                  <tr
                    :for={{id, doc} <- @streams.documents}
                    id={id}
                    class="hover:bg-gray-50 transition-colors"
                  >
                    <td class="px-4 py-3">
                      <.link
                        navigate={~p"/documents/#{doc.id}"}
                        class="text-sm font-medium text-blue-600 hover:text-blue-800"
                      >
                        {doc.title || doc.file_name}
                      </.link>
                    </td>
                    <td class="px-4 py-3 text-sm text-base-content/80">
                      {(doc.document_type && doc.document_type.name) || "—"}
                    </td>
                    <td class="px-4 py-3 text-sm text-base-content/80">
                      {(doc.correspondent && doc.correspondent.name) || "—"}
                    </td>
                    <td class="px-4 py-3">
                      <div class="flex flex-wrap gap-1">
                        <span
                          :for={tag <- doc.tags}
                          class="inline-block px-2 py-0.5 bg-blue-100 text-blue-800 rounded text-xs font-medium"
                        >
                          {tag.name}
                        </span>
                        <span :if={doc.tags == []} class="text-sm text-base-content/40">—</span>
                      </div>
                    </td>
                    <td class="px-4 py-3 text-sm text-base-content/80 whitespace-nowrap">
                      {format_date(doc.inserted_at)}
                    </td>
                    <td class="px-4 py-3">
                      <span class={[
                        "inline-block px-2.5 py-0.5 rounded-full text-xs font-medium",
                        status_badge_class(doc.status)
                      ]}>
                        {doc.status}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <.link
                        navigate={~p"/documents/#{doc.id}"}
                        class="text-sm text-base-content/60 hover:text-blue-600 transition-colors"
                      >
                        <.icon name="hero-eye" class="w-4 h-4 inline" />
                      </.link>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Pagination --%>
            <div :if={@pages > 1} class="flex items-center justify-between mt-4">
              <div class="text-sm text-base-content/70">
                Page {@page} of {@pages}
              </div>
              <div class="flex items-center gap-1">
                <button
                  phx-click="page"
                  phx-value-page={@page - 1}
                  disabled={@page <= 1}
                  class={[
                    "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
                    if(@page <= 1,
                      do: "text-base-content/30 cursor-not-allowed",
                      else: "text-base-content/70 hover:bg-gray-100"
                    )
                  ]}
                >
                  <.icon name="hero-chevron-left" class="w-4 h-4" />
                </button>

                <button
                  :for={p <- visible_pages(@page, @pages)}
                  phx-click="page"
                  phx-value-page={p}
                  class={[
                    "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors min-w-[2rem]",
                    if(p == @page,
                      do: "bg-blue-600 text-white",
                      else: "text-base-content/70 hover:bg-gray-100"
                    )
                  ]}
                >
                  {p}
                </button>

                <button
                  phx-click="page"
                  phx-value-page={@page + 1}
                  disabled={@page >= @pages}
                  class={[
                    "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
                    if(@page >= @pages,
                      do: "text-base-content/30 cursor-not-allowed",
                      else: "text-base-content/70 hover:bg-gray-100"
                    )
                  ]}
                >
                  <.icon name="hero-chevron-right" class="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp build_query(socket, filters, page, overrides \\ []) do
    sort_by = overrides[:sort_by] || socket.assigns.sort_by
    sort_order = overrides[:sort_order] || socket.assigns.sort_order
    search = overrides[:search] || socket.assigns.search

    params = %{
      page: page,
      sort_by: sort_by,
      sort_order: sort_order,
      search: search
    }

    params =
      if filters[:status] && filters[:status] != "" do
        Map.put(params, :status, filters[:status])
      else
        params
      end

    params =
      if filters[:tag_ids] && filters[:tag_ids] != [] do
        Map.put(params, :tag_ids, Enum.join(filters[:tag_ids], ","))
      else
        params
      end

    params =
      if filters[:document_type_id] && filters[:document_type_id] != "" do
        Map.put(params, :document_type_id, filters[:document_type_id])
      else
        params
      end

    params =
      if filters[:correspondent_id] && filters[:correspondent_id] != "" do
        Map.put(params, :correspondent_id, filters[:correspondent_id])
      else
        params
      end

    params =
      if filters[:date_from] && filters[:date_from] != "" do
        Map.put(params, :date_from, filters[:date_from])
      else
        params
      end

    params =
      if filters[:date_to] && filters[:date_to] != "" do
        Map.put(params, :date_to, filters[:date_to])
      else
        params
      end

    URI.encode_query(params)
  end

  defp parse_sort_order("asc"), do: :asc
  defp parse_sort_order("desc"), do: :desc
  defp parse_sort_order(_), do: :desc

  defp parse_list_param(nil), do: []
  defp parse_list_param(""), do: []
  defp parse_list_param(str), do: String.split(str, ",")

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(val), do: val

  defp empty_list_to_nil([]), do: nil
  defp empty_list_to_nil(list), do: list

  defp total_pages(total, per_page) when total > 0, do: ceil(total / per_page)
  defp total_pages(_, _), do: 1

  defp visible_pages(_current, total) when total <= 7 do
    Enum.to_list(1..total)
  end

  defp visible_pages(current, total) do
    cond do
      current <= 3 -> [1, 2, 3, 4, :ellipsis, total]
      current >= total - 2 -> [1, :ellipsis, total - 3, total - 2, total - 1, total]
      true -> [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end

  defp format_count(total, page, per_page) do
    start_item = (page - 1) * per_page + 1
    end_item = min(page * per_page, total)

    if total == 0 do
      "No documents found"
    else
      "Showing #{start_item}-#{end_item} of #{total} document#{if total != 1, do: "s"}"
    end
  end

  attr :active, :boolean, required: true
  attr :order, :atom, required: true

  defp sort_icon(assigns) do
    ~H"""
    <.icon
      name={if @active && @order == :asc, do: "hero-arrow-up", else: "hero-arrow-down"}
      class={[
        "w-4 h-4 inline ml-1 transition-opacity",
        @active && "opacity-100",
        !@active && "opacity-0 group-hover:opacity-40"
      ]}
    />
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
