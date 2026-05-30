defmodule SeathWeb.DocumentIndexLive do
  use SeathWeb, :live_view

  @per_page 20

  @impl true
  def mount(_params, _session, socket) do
    tags = Seath.Tags.list_tags()
    types = Seath.DocumentTypes.list_types()
    correspondents = Seath.Correspondents.list_correspondents()
    saved_searches = Seath.SavedSearches.list_saved_searches()

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
     |> assign(:saved_searches, saved_searches)
     |> assign(:sidebar_open, false)
     |> assign(:total_count, 0)
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, :desc)
     |> assign(:search, "")
     |> assign(:filters, %{})
     |> assign(:selected_ids, MapSet.new())
     |> assign(:saving_search, false)
     |> assign(:save_search_name, "")
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
      involved_party: params["involved_party"] || "",
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
      involved_party: blank_to_nil(filters.involved_party),
      date_from: blank_to_nil(filters.date_from),
      date_to: blank_to_nil(filters.date_to)
    ]

    saved_searches = Seath.SavedSearches.list_saved_searches()

    {documents, total_count} = Seath.Documents.list_documents_paginated(opts)

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:search, search)
     |> assign(:filters, filters)
     |> assign(:saved_searches, saved_searches)
     |> assign(:total_count, total_count)
     |> assign(:pages, total_pages(total_count, @per_page))
     |> assign(:no_results, documents == [])
     |> stream(:documents, documents, reset: true)}
  end

  @impl true
  def handle_info({:document_updated, _payload}, socket) do
    {documents, total_count} =
      Seath.Documents.list_documents_paginated(
        page: socket.assigns.page,
        per_page: socket.assigns.per_page,
        sort_by: socket.assigns.sort_by,
        sort_order: socket.assigns.sort_order,
        search: socket.assigns.search,
        status: blank_to_nil(socket.assigns.filters.status),
        tag_ids: empty_list_to_nil(socket.assigns.filters.tag_ids),
        document_type_id: blank_to_nil(socket.assigns.filters.document_type_id),
        correspondent_id: blank_to_nil(socket.assigns.filters.correspondent_id),
        involved_party: blank_to_nil(socket.assigns.filters.involved_party),
        date_from: blank_to_nil(socket.assigns.filters.date_from),
        date_to: blank_to_nil(socket.assigns.filters.date_to)
      )

    {:noreply,
     socket
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
      involved_party: filters_params["involved_party"] || "",
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

  # --- Saved Searches ---

  @impl true
  def handle_event("start_save_search", _params, socket) do
    {:noreply, socket |> assign(:saving_search, true) |> assign(:save_search_name, "")}
  end

  @impl true
  def handle_event("cancel_save_search", _params, socket) do
    {:noreply, socket |> assign(:saving_search, false) |> assign(:save_search_name, "")}
  end

  @impl true
  def handle_event("save_search", %{"name" => name}, socket) when name != "" do
    filters = socket.assigns.filters
    name = String.trim(name)

    attrs = %{
      name: name,
      query: socket.assigns.search,
      tag_ids: filters.tag_ids,
      status_filter: filters.status,
      document_type_id: blank_to_nil(filters.document_type_id),
      date_from: date_string_to_date(filters.date_from),
      date_to: date_string_to_date(filters.date_to)
    }

    case Seath.SavedSearches.create_saved_search(attrs) do
      {:ok, _search} ->
        saved_searches = Seath.SavedSearches.list_saved_searches()

        {:noreply,
         socket
         |> assign(:saved_searches, saved_searches)
         |> assign(:saving_search, false)
         |> assign(:save_search_name, "")
         |> put_flash(:info, "Saved search \"#{name}\".")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save search.")}
    end
  end

  def handle_event("save_search", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_saved_search", %{"id" => id}, socket) do
    search = Seath.SavedSearches.get_saved_search!(id)
    filters = socket.assigns.filters

    updated_filters = %{
      filters
      | tag_ids: search.tag_ids || [],
        status: search.status_filter || "",
        document_type_id: search.document_type_id || "",
        date_from: date_to_string(search.date_from),
        date_to: date_to_string(search.date_to)
    }

    {:noreply,
     push_patch(socket,
       to: ~p"/documents?#{build_query(socket, updated_filters, 1, search: search.query || "")}"
     )}
  end

  @impl true
  def handle_event("delete_saved_search", %{"id" => id}, socket) do
    search = Seath.SavedSearches.get_saved_search!(id)
    name = search.name
    Seath.SavedSearches.delete_saved_search(search)
    saved_searches = Seath.SavedSearches.list_saved_searches()

    {:noreply,
     socket
     |> assign(:saved_searches, saved_searches)
     |> put_flash(:info, "Deleted saved search \"#{name}\".")}
  end

  # --- Bulk Selection ---

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected_ids =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids =
      socket.streams.documents
      |> Enum.map(fn {_id, doc} -> doc.id end)
      |> MapSet.new()

    {:noreply, assign(socket, :selected_ids, all_ids)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("bulk_add_tag", %{"tag_id" => tag_id}, socket) do
    if tag_id != "" do
      tag = Seath.Tags.get_tag!(tag_id)
      count = MapSet.size(socket.assigns.selected_ids)

      socket.assigns.selected_ids
      |> Enum.each(fn id ->
        doc = Seath.Documents.get_document!(id)
        Seath.Tags.add_tag_to_document(doc, tag)
      end)

      {documents, total_count} =
        Seath.Documents.list_documents_paginated(
          page: socket.assigns.page,
          per_page: socket.assigns.per_page,
          sort_by: socket.assigns.sort_by,
          sort_order: socket.assigns.sort_order,
          search: socket.assigns.search
        )

      {:noreply,
       socket
       |> assign(:total_count, total_count)
       |> assign(:pages, total_pages(total_count, @per_page))
       |> assign(:no_results, documents == [])
       |> assign(:selected_ids, MapSet.new())
       |> stream(:documents, documents, reset: true)
       |> put_flash(:info, "Tag '#{tag.name}' added to #{count} document(s).")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("bulk_remove_tag", %{"tag_id" => tag_id}, socket) do
    if tag_id != "" do
      tag = Seath.Tags.get_tag!(tag_id)
      count = MapSet.size(socket.assigns.selected_ids)

      socket.assigns.selected_ids
      |> Enum.each(fn id ->
        doc = Seath.Documents.get_document!(id)
        Seath.Tags.remove_tag_from_document(doc, tag)
      end)

      {documents, total_count} =
        Seath.Documents.list_documents_paginated(
          page: socket.assigns.page,
          per_page: socket.assigns.per_page,
          sort_by: socket.assigns.sort_by,
          sort_order: socket.assigns.sort_order,
          search: socket.assigns.search
        )

      {:noreply,
       socket
       |> assign(:total_count, total_count)
       |> assign(:pages, total_pages(total_count, @per_page))
       |> assign(:no_results, documents == [])
       |> assign(:selected_ids, MapSet.new())
       |> stream(:documents, documents, reset: true)
       |> put_flash(:info, "Tag '#{tag.name}' removed from #{count} document(s).")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)

    case Seath.Documents.delete_document(doc) do
      {:ok, _deleted} ->
        {:noreply,
         socket
         |> stream_delete(:documents, doc)
         |> put_flash(:info, "Document deleted.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete: #{reason}")}
    end
  end

  @impl true
  def handle_event("retry_document_index", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, _updated} = Seath.Documents.retry_failed(doc)

    {documents, total_count} =
      Seath.Documents.list_documents_paginated(
        page: socket.assigns.page,
        per_page: socket.assigns.per_page,
        sort_by: socket.assigns.sort_by,
        sort_order: socket.assigns.sort_order,
        search: socket.assigns.search,
        status: blank_to_nil(socket.assigns.filters.status),
        tag_ids: empty_list_to_nil(socket.assigns.filters.tag_ids),
        document_type_id: blank_to_nil(socket.assigns.filters.document_type_id),
        correspondent_id: blank_to_nil(socket.assigns.filters.correspondent_id),
        involved_party: blank_to_nil(socket.assigns.filters.involved_party),
        date_from: blank_to_nil(socket.assigns.filters.date_from),
        date_to: blank_to_nil(socket.assigns.filters.date_to)
      )

    {:noreply,
     socket
     |> assign(:total_count, total_count)
     |> assign(:pages, total_pages(total_count, @per_page))
     |> assign(:no_results, documents == [])
     |> stream(:documents, documents, reset: true)
     |> put_flash(:info, "Document queued for retry.")}
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

              <%!-- Involved Party --%>
              <div class="mb-4">
                <label class="block text-xs font-semibold text-base-content/80 mb-2 uppercase tracking-wider">
                  Involved Party
                </label>
                <input
                  type="text"
                  name="involved_party"
                  value={@filters.involved_party}
                  placeholder="Filter by name..."
                  phx-debounce="300"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
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

            <%!-- Save Current Filters --%>
            <div class="border-t border-gray-200 pt-4 mt-4">
              <%= if @saving_search do %>
                <form phx-submit="save_search" class="space-y-2">
                  <input
                    type="text"
                    name="name"
                    value={@save_search_name}
                    placeholder="Search name..."
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    autofocus
                  />
                  <div class="flex gap-2">
                    <button
                      type="submit"
                      class="flex-1 px-3 py-1.5 bg-blue-600 text-white rounded-lg text-xs font-medium hover:bg-blue-700 transition-colors"
                    >
                      Save
                    </button>
                    <button
                      type="button"
                      phx-click="cancel_save_search"
                      class="px-3 py-1.5 border border-gray-300 text-base-content/70 rounded-lg text-xs font-medium hover:bg-gray-50 transition-colors"
                    >
                      Cancel
                    </button>
                  </div>
                </form>
              <% else %>
                <button
                  phx-click="start_save_search"
                  class="w-full px-3 py-2 border border-dashed border-gray-300 text-base-content/60 rounded-lg text-xs font-medium hover:border-blue-400 hover:text-blue-600 transition-colors flex items-center justify-center gap-1.5"
                >
                  <.icon name="hero-bookmark" class="w-3.5 h-3.5" /> Save Current Filters
                </button>
              <% end %>
            </div>

            <%!-- Saved Searches --%>
            <div :if={@saved_searches != []} class="border-t border-gray-200 pt-4 mt-4">
              <h4 class="text-xs font-semibold text-base-content/80 mb-3 uppercase tracking-wider">
                Saved Searches
              </h4>
              <div class="space-y-1">
                <div
                  :for={search <- @saved_searches}
                  class="group flex items-center justify-between px-2 py-1.5 rounded-lg hover:bg-gray-50 transition-colors"
                >
                  <button
                    phx-click="load_saved_search"
                    phx-value-id={search.id}
                    class="flex items-center gap-2 text-sm text-base-content/80 hover:text-blue-600 transition-colors"
                  >
                    <.icon name="hero-magnifying-glass" class="w-3.5 h-3.5 shrink-0" />
                    <span class="truncate">{search.name}</span>
                  </button>
                  <button
                    phx-click="delete_saved_search"
                    phx-value-id={search.id}
                    class="opacity-0 group-hover:opacity-100 text-base-content/40 hover:text-red-500 transition-all"
                  >
                    <.icon name="hero-trash" class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            </div>
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

            <%!-- Bulk action bar --%>
            <div
              :if={MapSet.size(@selected_ids) > 0}
              class="mb-4 p-4 bg-blue-50 border border-blue-200 rounded-lg flex items-center justify-between"
            >
              <div class="flex items-center gap-3">
                <span class="text-sm text-blue-800 font-medium">
                  {MapSet.size(@selected_ids)} document(s) selected
                </span>
                <button
                  phx-click="deselect_all"
                  class="text-xs text-blue-600 hover:text-blue-800 font-medium"
                >
                  Clear selection
                </button>
              </div>
              <div class="flex items-center gap-2">
                <form phx-change="bulk_add_tag" id="bulk-add-tag-form">
                  <select
                    name="tag_id"
                    class="px-3 py-1.5 border border-blue-300 bg-white rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="">Add tag...</option>
                    <option :for={tag <- @tags} value={tag.id}>{tag.name}</option>
                  </select>
                </form>
                <form phx-change="bulk_remove_tag" id="bulk-remove-tag-form">
                  <select
                    name="tag_id"
                    class="px-3 py-1.5 border border-blue-300 bg-white rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="">Remove tag...</option>
                    <option :for={tag <- @tags} value={tag.id}>{tag.name}</option>
                  </select>
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
                    <th class="px-4 py-3 w-10">
                      <input
                        type="checkbox"
                        phx-click={
                          if(MapSet.size(@selected_ids) > 0, do: "deselect_all", else: "select_all")
                        }
                        checked={MapSet.size(@selected_ids) > 0}
                        class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                    </th>
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
                    <td colspan="8" class="px-4 py-12 text-center">
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
                      <input
                        type="checkbox"
                        phx-click="toggle_select"
                        phx-value-id={doc.id}
                        checked={MapSet.member?(@selected_ids, doc.id)}
                        class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                    </td>
                    <td class="px-4 py-3">
                      <div class="flex items-center gap-3">
                        <img
                          src={~p"/documents/#{doc.id}/thumbnail"}
                          alt="Thumbnail"
                          class="shrink-0 w-12 h-12 rounded border object-cover bg-gray-50"
                          loading="lazy"
                        />
                        <.link
                          navigate={~p"/documents/#{doc.id}"}
                          class="text-sm font-medium text-blue-600 hover:text-blue-800"
                        >
                          {doc.title || doc.file_name}
                        </.link>
                      </div>
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
                      <div class="flex items-center justify-end gap-2">
                        <.link
                          navigate={~p"/documents/#{doc.id}"}
                          class="text-sm text-base-content/60 hover:text-blue-600 transition-colors"
                        >
                          <.icon name="hero-eye" class="w-4 h-4" />
                        </.link>
                        <button
                          :if={doc.status == "error"}
                          phx-click="retry_document_index"
                          phx-value-id={doc.id}
                          class="text-sm text-red-500 hover:text-red-700 transition-colors"
                          title="Retry document"
                        >
                          <.icon name="hero-arrow-path" class="w-4 h-4" />
                        </button>
                        <button
                          phx-click="delete"
                          phx-value-id={doc.id}
                          class="text-sm text-gray-400 hover:text-red-600 transition-colors"
                          title="Delete document"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                        </button>
                      </div>
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
      if filters[:involved_party] && filters[:involved_party] != "" do
        Map.put(params, :involved_party, filters[:involved_party])
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

  defp date_string_to_date(""), do: nil
  defp date_string_to_date(nil), do: nil

  defp date_string_to_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date_to_string(nil), do: ""
  defp date_to_string(%Date{} = date), do: Date.to_string(date)
  defp date_to_string(str) when is_binary(str), do: str
end
