defmodule SeathWeb.ReviewLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    documents = Seath.Documents.list_by_status("awaiting_review")
    tags = Seath.Tags.list_tags()
    types = Seath.DocumentTypes.list_types()
    correspondents = Seath.Correspondents.list_correspondents()

    Phoenix.PubSub.subscribe(Seath.PubSub, "documents")

    {:ok,
     socket
     |> assign(:documents, documents)
     |> assign(:tags, tags)
     |> assign(:types, types)
     |> assign(:correspondents, correspondents)
     |> assign(:selected_doc, nil)
     |> assign(:involved_parties, [])
     |> assign(:selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    doc =
      Seath.Documents.get_document!(id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    involved_parties = Seath.InvolvedParties.list_parties_by_document(id)

    {:noreply,
     assign(socket, :selected_doc, doc)
     |> assign(:involved_parties, involved_parties)}
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
     |> assign(:involved_parties, [])
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
     |> assign(:involved_parties, [])
     |> put_flash(:info, "Document rejected.")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)

    case Seath.Documents.delete_document(doc) do
      {:ok, _deleted} ->
        documents = Seath.Documents.list_by_status("awaiting_review")

        {:noreply,
         socket
         |> assign(:documents, documents)
         |> assign(:selected_doc, nil)
         |> assign(:involved_parties, [])
         |> put_flash(:info, "Document deleted.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete: #{reason}")}
    end
  end

  @impl true
  def handle_event("reclassify", %{"id" => id}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, _updated} = Seath.Documents.reclassify(doc)

    updated =
      Seath.Documents.get_document!(id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    {:noreply,
     socket
     |> assign(:selected_doc, updated)
     |> put_flash(
       :info,
       "Reclassification started for \"#{updated.title || updated.file_name}\"."
     )}
  end

  @impl true
  def handle_event("update_title", %{"id" => id, "title" => title}, socket) do
    doc = Seath.Documents.get_document!(id)
    {:ok, updated} = Seath.Documents.update_document(doc, %{title: title})
    updated = Seath.Repo.preload(updated, [:tags, :document_type, :correspondent])
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
      Seath.Documents.get_document!(id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def handle_event("create_tag", %{"id" => id, "name" => name}, socket) when name != "" do
    doc = Seath.Documents.get_document!(id)
    name = String.trim(name)

    tag =
      case Seath.Tags.get_tag_by_name(name) do
        nil ->
          {:ok, tag} = Seath.Tags.create_tag(%{name: name})
          tag

        existing ->
          existing
      end

    Seath.Tags.add_tag_to_document(doc, tag)
    tags = Seath.Tags.list_tags()
    updated = Seath.Repo.preload(doc, [:tags, :document_type, :correspondent])

    {:noreply,
     socket
     |> assign(:selected_doc, updated)
     |> assign(:tags, tags)}
  end

  def handle_event("create_tag", _params, socket), do: {:noreply, socket}

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
  def handle_event("bulk_approve", _params, socket) do
    Enum.each(socket.assigns.selected_ids, fn id ->
      doc = Seath.Documents.get_document!(id)
      Seath.Documents.transition_status(doc, "archived")
    end)

    count = MapSet.size(socket.assigns.selected_ids)
    documents = Seath.Documents.list_by_status("awaiting_review")

    {:noreply,
     socket
     |> assign(:documents, documents)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:selected_doc, nil)
     |> assign(:involved_parties, [])
     |> put_flash(:info, "#{count} document(s) approved and archived.")}
  end

  @impl true
  def handle_event("bulk_reject", _params, socket) do
    Enum.each(socket.assigns.selected_ids, fn id ->
      doc = Seath.Documents.get_document!(id)
      Seath.Documents.transition_status(doc, "rejected")
    end)

    count = MapSet.size(socket.assigns.selected_ids)
    documents = Seath.Documents.list_by_status("awaiting_review")

    {:noreply,
     socket
     |> assign(:documents, documents)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:selected_doc, nil)
     |> assign(:involved_parties, [])
     |> put_flash(:info, "#{count} document(s) rejected.")}
  end

  @impl true
  def handle_event("update_type", %{"id" => id, "document_type_id" => type_id}, socket) do
    doc = Seath.Documents.get_document!(id)
    type_id = if type_id == "", do: nil, else: type_id
    {:ok, updated} = Seath.Documents.update_document(doc, %{document_type_id: type_id})
    updated = Seath.Repo.preload(updated, [:tags, :document_type, :correspondent])
    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def handle_event("create_type", %{"id" => id, "name" => name}, socket) when name != "" do
    name = String.trim(name)

    type =
      case Seath.DocumentTypes.get_type_by_name(name) do
        nil ->
          {:ok, t} = Seath.DocumentTypes.create_type(%{name: name})
          t

        existing ->
          existing
      end

    doc = Seath.Documents.get_document!(id)
    {:ok, updated} = Seath.Documents.update_document(doc, %{document_type_id: type.id})
    updated = Seath.Repo.preload(updated, [:tags, :document_type, :correspondent])
    types = Seath.DocumentTypes.list_types()

    {:noreply,
     socket
     |> assign(:selected_doc, updated)
     |> assign(:types, types)
     |> put_flash(:info, "Type '#{type.name}' created and assigned.")}
  end

  def handle_event("create_type", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_correspondent", %{"id" => id, "correspondent_id" => corr_id}, socket) do
    doc = Seath.Documents.get_document!(id)
    corr_id = if corr_id == "", do: nil, else: corr_id
    {:ok, updated} = Seath.Documents.update_document(doc, %{correspondent_id: corr_id})
    updated = Seath.Repo.preload(updated, [:tags, :document_type, :correspondent])
    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def handle_event("remove_involved_party", %{"party_id" => party_id}, socket) do
    party = Seath.InvolvedParties.get_involved_party!(party_id)
    {:ok, _} = Seath.InvolvedParties.delete_involved_party(party)

    parties = Seath.InvolvedParties.list_parties_by_document(socket.assigns.selected_doc.id)
    {:noreply, assign(socket, :involved_parties, parties)}
  end

  def handle_event("remove_tag", %{"id" => id, "tag_id" => tag_id}, socket) do
    doc = Seath.Documents.get_document!(id)
    tag = Seath.Tags.get_tag!(tag_id)
    Seath.Tags.remove_tag_from_document(doc, tag)

    updated =
      Seath.Documents.get_document!(id)
      |> Seath.Repo.preload([:tags, :document_type, :correspondent])

    {:noreply, assign(socket, :selected_doc, updated)}
  end

  @impl true
  def handle_info({:document_updated, %{id: id, status: status}}, socket) do
    socket =
      if socket.assigns.selected_doc && socket.assigns.selected_doc.id == id do
        if status == "awaiting_review" do
          doc =
            Seath.Documents.get_document!(id)
            |> Seath.Repo.preload([:tags, :document_type, :correspondent])

          assign(socket, :selected_doc, doc)
        else
          assign(socket, :selected_doc, %{socket.assigns.selected_doc | status: status})
        end
      else
        socket
      end

    documents = Seath.Documents.list_by_status("awaiting_review")
    {:noreply, assign(socket, :documents, documents)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:review} review_count={length(@documents)}>
      <div class="max-w-7xl mx-auto py-8 px-4">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Document Review</h1>
            <p class="text-base-content/90 text-sm mt-1">
              {length(@documents)} document(s) awaiting review
            </p>
          </div>

          <%!-- Bulk action bar --%>
          <div :if={MapSet.size(@selected_ids) > 0} class="flex items-center gap-3">
            <span class="text-sm text-blue-800 font-medium">
              {MapSet.size(@selected_ids)} selected
            </span>
            <button
              phx-click="bulk_approve"
              class="px-4 py-2 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 transition-colors"
            >
              Approve Selected
            </button>
            <button
              phx-click="bulk_reject"
              class="px-4 py-2 bg-red-600 text-white rounded-lg text-sm font-medium hover:bg-red-700 transition-colors"
            >
              Reject Selected
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-5 gap-6">
          <%!-- Document list sidebar --%>
          <div class="lg:col-span-1 space-y-2">
            <div
              :for={doc <- @documents}
              id={"doc-list-item-#{doc.id}"}
              class={[
                "flex items-center gap-2 p-3 rounded-lg border bg-white transition-colors cursor-pointer",
                if(@selected_doc && @selected_doc.id == doc.id,
                  do: "border-blue-500 bg-blue-50 ring-1 ring-blue-200",
                  else: "border-gray-200 hover:border-gray-300 hover:bg-gray-50"
                )
              ]}
              phx-click="select"
              phx-value-id={doc.id}
            >
              <input
                type="checkbox"
                phx-click="toggle_select"
                phx-value-id={doc.id}
                checked={MapSet.member?(@selected_ids, doc.id)}
                class="rounded border-gray-300 shrink-0"
                onclick="event.stopPropagation()"
              />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-base-content truncate">
                  {doc.title || doc.file_name}
                </p>
                <p class="text-xs text-base-content/70 mt-0.5">
                  {format_file_size(doc.file_size)}
                </p>
              </div>
            </div>

            <div :if={@documents == []} class="text-center py-12 text-base-content/90">
              <.icon name="hero-inbox" class="w-10 h-10 mx-auto mb-2 text-base-content/90" />
              <p class="text-sm text-base-content font-medium">No documents awaiting review</p>
            </div>
          </div>

          <%!-- Detail pane --%>
          <div :if={@selected_doc} class="lg:col-span-4 space-y-6">
            <%!-- Document preview --%>
            <div class="bg-white rounded-xl border overflow-hidden">
              <%= cond do %>
                <% @selected_doc.file_type == "application/pdf" -> %>
                  <object
                    data={"/documents/#{@selected_doc.id}/file"}
                    type="application/pdf"
                    class="w-full min-h-[500px]"
                  >
                    <p class="p-4 text-sm text-base-content/60">
                      Your browser doesn't support embedded PDF viewing.
                      <a
                        href={"/documents/#{@selected_doc.id}/download"}
                        class="text-blue-600 hover:text-blue-800 underline"
                      >Download the PDF</a> to view it.
                    </p>
                  </object>
                <% String.starts_with?(@selected_doc.file_type, "image/") -> %>
                  <img
                    src={"/documents/#{@selected_doc.id}/file"}
                    alt={"Preview of #{@selected_doc.title || @selected_doc.file_name}"}
                    class="w-full h-auto object-contain max-h-[600px]"
                    loading="lazy"
                  />
                <% true -> %>
                  <div class="flex items-center justify-center min-h-[200px] bg-gray-50">
                    <p class="text-sm text-base-content/40">Preview not available for this file type.</p>
                  </div>
              <% end %>
            </div>

            <%!-- Metadata & actions panel --%>
            <div class="bg-white rounded-xl border p-6">
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-x-8 gap-y-6">
                <%!-- Title --%>
                <div class="lg:col-span-2">
                  <label class="block text-sm font-semibold text-base-content mb-1">Title</label>
                  <form phx-change="update_title" phx-value-id={@selected_doc.id}>
                    <input
                      type="text"
                      name="title"
                      value={@selected_doc.title}
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    />
                  </form>
                </div>

                <%!-- Document type --%>
                <div>
                  <label class="block text-sm font-semibold text-base-content mb-1">
                    Document Type
                  </label>
                  <form phx-change="update_type" phx-value-id={@selected_doc.id}>
                    <div class="flex gap-1">
                      <select
                        name="document_type_id"
                        class="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                      >
                        <option value="">None</option>
                        <option
                          :for={type <- @types}
                          value={type.id}
                          selected={
                            @selected_doc.document_type && @selected_doc.document_type.id == type.id
                          }
                        >
                          {type.name}
                        </option>
                      </select>
                      <form
                        phx-submit="create_type"
                        phx-value-id={@selected_doc.id}
                        class="flex gap-1"
                      >
                        <input
                          type="text"
                          name="name"
                          placeholder="New..."
                          class="w-24 px-2 py-2 border border-gray-300 rounded-lg text-xs focus:ring-2 focus:ring-blue-500"
                        />
                        <button
                          type="submit"
                          class="px-2 py-2 bg-blue-600 text-white rounded-lg text-xs hover:bg-blue-700 transition-colors"
                        >
                          Add
                        </button>
                      </form>
                    </div>
                  </form>
                </div>

                <%!-- Correspondent --%>
                <div>
                  <label class="block text-sm font-semibold text-base-content mb-1">
                    Correspondent
                  </label>
                  <form phx-change="update_correspondent" phx-value-id={@selected_doc.id}>
                    <select
                      name="correspondent_id"
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                    >
                      <option value="">None</option>
                      <option
                        :for={corr <- @correspondents}
                        value={corr.id}
                        selected={
                          @selected_doc.correspondent && @selected_doc.correspondent.id == corr.id
                        }
                      >
                        {corr.name}
                      </option>
                    </select>
                  </form>
                </div>

                <%!-- Confidence --%>
                <div :if={@selected_doc.confidence}>
                  <label class="block text-sm font-semibold text-base-content mb-1">
                    Classification Confidence
                  </label>
                  <div class="flex items-center gap-3">
                    <div class="flex-1 bg-gray-200 rounded-full h-3">
                      <div
                        class={[
                          "h-3 rounded-full transition-all",
                          @selected_doc.confidence >= 0.8 && "bg-green-500",
                          @selected_doc.confidence >= 0.5 && @selected_doc.confidence < 0.8 && "bg-yellow-500",
                          @selected_doc.confidence < 0.5 && "bg-red-500"
                        ]}
                        style={"width: #{Float.round(@selected_doc.confidence * 100)}%"}
                      >
                      </div>
                    </div>
                    <span class={[
                      "text-sm font-medium shrink-0",
                      @selected_doc.confidence >= 0.8 && "text-green-700",
                      @selected_doc.confidence >= 0.5 && @selected_doc.confidence < 0.8 && "text-yellow-700",
                      @selected_doc.confidence < 0.5 && "text-red-700"
                    ]}>
                      {Float.round(@selected_doc.confidence * 100, 1)}%
                    </span>
                  </div>
                </div>

                <%!-- Classification attempts & JEV badges --%>
                <div class="flex flex-wrap items-center gap-2">
                  <span
                    :if={
                      @selected_doc.classification_attempts &&
                        @selected_doc.classification_attempts > 0
                    }
                    class="text-xs text-base-content/70"
                  >
                    Attempt {@selected_doc.classification_attempts}
                  </span>
                  <span
                    :if={jev_calibrated?(@selected_doc)}
                    class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-emerald-100 text-emerald-800"
                  >
                    <.icon name="hero-shield-check" class="w-3.5 h-3.5" /> JEV Calibrated
                  </span>
                  <span
                    :if={actionable_doc?(@selected_doc)}
                    class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800"
                  >
                    <.icon name="hero-bolt" class="w-3.5 h-3.5" /> Actionable
                  </span>
                  <span
                    :if={needs_human_review?(@selected_doc)}
                    class="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium bg-rose-100 text-rose-800"
                  >
                    <.icon name="hero-eye" class="w-3.5 h-3.5" /> Needs Human Review
                  </span>
                </div>
              </div>

              <%!-- AI Summary & Extracted Insights --%>
              <% insights = extract_ai_insights(@selected_doc) %>
              <div
                :if={
                  insights.summary != "" or insights.amounts != [] or insights.dates != []
                }
                class="mt-6 p-4 bg-slate-50 border border-slate-200 rounded-lg space-y-3"
              >
                <div :if={insights.summary != ""}>
                  <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                    AI Summary
                  </p>
                  <p class="text-sm text-base-content/90">{insights.summary}</p>
                </div>
                <div
                  :if={insights.amounts != [] or insights.dates != []}
                  class="flex flex-wrap gap-6 pt-1"
                >
                  <div :if={insights.amounts != []}>
                    <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Extracted Amounts
                    </p>
                    <div class="flex flex-wrap gap-1.5">
                      <span
                        :for={amt <- insights.amounts}
                        class="px-2 py-0.5 bg-green-100 text-green-800 rounded text-xs font-mono font-medium"
                      >
                        {amt}
                      </span>
                    </div>
                  </div>
                  <div :if={insights.dates != []}>
                    <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wider mb-1">
                      Extracted Dates
                    </p>
                    <div class="flex flex-wrap gap-1.5">
                      <span
                        :for={dt <- insights.dates}
                        class="px-2 py-0.5 bg-purple-100 text-purple-800 rounded text-xs font-mono font-medium"
                      >
                        {dt}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- Verification warnings --%>
              <div
                :if={
                  @selected_doc.verification_data &&
                    (@selected_doc.verification_data["passed"] == false or
                       @selected_doc.verification_data[:passed] == false) &&
                    length(
                      @selected_doc.verification_data["flagged_fields"] ||
                        @selected_doc.verification_data[:flagged_fields] || []
                    ) > 0
                }
                class="mt-6 p-3 bg-yellow-50 border border-yellow-200 rounded-lg"
              >
                <div class="flex items-start gap-2">
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-5 h-5 text-yellow-600 shrink-0 mt-0.5"
                  />
                  <div>
                    <p class="text-sm font-medium text-yellow-800">Verification Flags</p>
                    <ul class="mt-1 text-sm text-yellow-700 list-disc list-inside">
                      <li :for={
                        field <-
                          @selected_doc.verification_data["flagged_fields"] ||
                            @selected_doc.verification_data[:flagged_fields] || []
                      }>
                        {format_flagged_field(field)}
                      </li>
                    </ul>
                  </div>
                </div>
              </div>

              <%!-- Tags --%>
              <div class="mt-6">
                <label class="block text-sm font-semibold text-base-content mb-2">Tags</label>
                <div class="flex flex-wrap gap-2 mb-3">
                  <span
                    :for={tag <- @selected_doc.tags}
                    class="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 text-blue-900 rounded-full text-sm font-medium"
                  >
                    {tag.name}
                    <button
                      phx-click="remove_tag"
                      phx-value-id={@selected_doc.id}
                      phx-value-tag_id={tag.id}
                      class="ml-1 hover:text-blue-600"
                    >
                      <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                    </button>
                  </span>
                </div>
                <div class="flex gap-2">
                  <form phx-change="add_tag" phx-value-id={@selected_doc.id} class="flex-1">
                    <select
                      name="tag_id"
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                    >
                      <option value="">Add existing tag...</option>
                      <option :for={tag <- @tags} value={tag.id}>{tag.name}</option>
                    </select>
                  </form>
                  <form phx-submit="create_tag" phx-value-id={@selected_doc.id} class="flex gap-1">
                    <input
                      type="text"
                      name="name"
                      placeholder="New tag..."
                      class="w-24 px-2 py-2 border border-gray-300 rounded-lg text-xs"
                    />
                    <button
                      type="submit"
                      class="px-2 py-2 bg-blue-600 text-white rounded-lg text-xs hover:bg-blue-700"
                    >
                      Add
                    </button>
                  </form>
                </div>
              </div>

              <%!-- Involved Parties --%>
              <div class="mt-6">
                <label class="block text-sm font-semibold text-base-content mb-2">
                  Involved Parties
                </label>
                <div :if={@involved_parties && @involved_parties != []} class="space-y-2">
                  <div
                    :for={party <- @involved_parties}
                    class="flex items-center justify-between px-3 py-2 bg-gray-50 rounded-lg"
                  >
                    <div class="min-w-0">
                      <span class="text-sm font-medium text-base-content">{party.name}</span>
                      <span class="text-xs text-base-content/70 ml-2">({party.role})</span>
                    </div>
                    <button
                      phx-click="remove_involved_party"
                      phx-value-party_id={party.id}
                      class="text-red-500 hover:text-red-700 shrink-0"
                    >
                      <.icon name="hero-x-mark" class="w-4 h-4" />
                    </button>
                  </div>
                </div>
                <p
                  :if={!@involved_parties || @involved_parties == []}
                  class="text-sm text-base-content/70"
                >
                  No involved parties extracted
                </p>
              </div>

              <%!-- Actions --%>
              <div class="flex gap-3 mt-6 pt-6 border-t">
                <button
                  id="reclassify-btn"
                  phx-click="reclassify"
                  phx-value-id={@selected_doc.id}
                  disabled={@selected_doc.status == "processing"}
                  class={[
                    "flex-1 py-2.5 px-4 rounded-lg font-medium transition-colors border text-sm",
                    if @selected_doc.status == "processing" do
                      "border-gray-200 bg-gray-100 text-gray-400 cursor-not-allowed"
                    else
                      "border-gray-300 bg-white text-base-content hover:bg-gray-50"
                    end
                  ]}
                >
                  <%= if @selected_doc.status == "processing" do %>
                    <.icon name="hero-arrow-path" class="w-4 h-4 inline mr-1 animate-spin" />
                    Reclassifying...
                  <% else %>
                    <.icon name="hero-arrow-clockwise" class="w-4 h-4 inline mr-1" /> Reclassify
                  <% end %>
                </button>
                <button
                  id="approve-btn"
                  phx-click="approve"
                  phx-value-id={@selected_doc.id}
                  class="flex-1 bg-green-600 text-white py-2.5 px-4 rounded-lg font-medium text-sm hover:bg-green-700 transition-colors"
                >
                  <.icon name="hero-check" class="w-4 h-4 inline mr-1" /> Approve &amp; Archive
                </button>
                <button
                  id="reject-btn"
                  phx-click="reject"
                  phx-value-id={@selected_doc.id}
                  class="flex-1 bg-red-600 text-white py-2.5 px-4 rounded-lg font-medium text-sm hover:bg-red-700 transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4 inline mr-1" /> Reject
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={@selected_doc.id}
                  class="py-2.5 px-4 rounded-lg font-medium text-sm border border-gray-300 text-base-content/70 hover:bg-gray-50 transition-colors"
                >
                  <.icon name="hero-trash" class="w-4 h-4 inline mr-1" /> Delete
                </button>
              </div>
            </div>

            <%!-- OCR text (collapsible) --%>
            <div class="bg-white rounded-xl border overflow-hidden">
              <details class="group">
                <summary class="flex items-center gap-2 px-6 py-4 cursor-pointer hover:bg-gray-50 transition-colors list-none">
                  <.icon name="hero-document-text" class="w-5 h-5 text-base-content/70 shrink-0" />
                  <span class="text-sm font-semibold text-base-content">Extracted Text</span>
                  <span class="text-xs text-base-content/50 ml-auto">
                    <%= if @selected_doc.ocr_text do %>
                      {String.length(@selected_doc.ocr_text)} chars
                    <% end %>
                  </span>
                  <.icon
                    name="hero-chevron-down"
                    class="w-4 h-4 text-base-content/50 transition-transform group-open:rotate-180"
                  />
                </summary>
                <div class="border-t px-6 py-4 bg-gray-50">
                  <pre class="whitespace-pre-wrap text-xs font-mono leading-relaxed text-base-content/90 max-h-[500px] overflow-y-auto">
                    {if @selected_doc.ocr_text,
                      do: @selected_doc.ocr_text,
                      else: "No text extracted"}
                  </pre>
                </div>
              </details>
            </div>
          </div>

          <%!-- Empty state --%>
          <div :if={!@selected_doc} class="lg:col-span-4 flex items-center justify-center min-h-[400px]">
            <div class="text-center text-base-content/90">
              <.icon
                name="hero-document-magnifying-glass"
                class="w-16 h-16 mx-auto mb-4 text-base-content/90"
              />
              <p class="text-lg text-base-content font-medium">Select a document to review</p>
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

  defp format_flagged_field(%{"field" => field, "reason" => reason}) do
    "#{field}: #{reason}"
  end

  defp format_flagged_field(%{field: field, reason: reason}) do
    "#{field}: #{reason}"
  end

  defp format_flagged_field(%{"field" => field}) do
    "#{field} not found in document text"
  end

  defp format_flagged_field(%{field: field}) do
    "#{field} not found in document text"
  end

  defp format_flagged_field(field) when is_binary(field) do
    "#{field} not found in document text"
  end

  defp format_flagged_field(other), do: inspect(other)

  defp jev_calibrated?(doc) do
    vf =
      (doc.verification_data &&
         (doc.verification_data["verified_fields"] || doc.verification_data[:verified_fields])) ||
        []

    is_list(vf) and "jev_calibrated" in vf
  end

  defp actionable_doc?(doc) do
    vd = doc.verification_data || %{}

    vd["is_actionable"] == true or vd[:is_actionable] == true or
      extract_classification_bool(doc, "is_actionable")
  end

  defp needs_human_review?(doc) do
    vd = doc.verification_data || %{}

    vd["needs_human_review"] == true or vd[:needs_human_review] == true or
      extract_classification_bool(doc, "needs_human_review")
  end

  defp extract_classification_bool(doc, key) do
    case parse_reasoning_json(doc.llm_reasoning) do
      %{"classification" => class_map} when is_map(class_map) ->
        Map.get(class_map, key) == true

      _ ->
        false
    end
  end

  defp extract_ai_insights(doc) do
    case parse_reasoning_json(doc.llm_reasoning) do
      %{"thinking" => thinking} when is_map(thinking) ->
        %{
          summary: to_string(thinking["summary"] || ""),
          amounts: List.wrap(thinking["extracted_amounts"] || []),
          dates: List.wrap(thinking["extracted_dates"] || [])
        }

      _ ->
        %{summary: "", amounts: [], dates: []}
    end
  end

  defp parse_reasoning_json(bin) when is_binary(bin) and bin != "" do
    case Jason.decode(bin) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_reasoning_json(_), do: %{}
end
