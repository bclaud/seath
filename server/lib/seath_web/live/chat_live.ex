defmodule SeathWeb.ChatLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:query, "")
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("submit", %{"query" => query}, socket) when query != "" do
    socket = assign(socket, :loading, true)

    user_msg = %{role: :user, content: query}

    case Seath.LLM.embed(query) do
      {:ok, query_embedding} ->
        similar =
          Seath.Embeddings.similarity_search(query_embedding, limit: 3, min_score: 0.5)

        context_parts =
          Enum.map(similar, fn %{document: doc} ->
            "--- Document: #{doc.title || doc.file_name} ---\n#{String.slice(doc.ocr_text || "", 0, 1000)}"
          end)

        context = Enum.join(context_parts, "\n\n")

        prompt = """
        Answer the question based on the provided documents.

        Context documents:
        #{context}

        Question: #{query}

        Answer concisely based only on the provided context. If the context doesn't contain relevant information, say so.
        """

        case Seath.LLM.classify(prompt, [], []) do
          {:ok, %{title: answer}} ->
            assistant_msg = %{role: :assistant, content: answer, sources: similar}

            {:noreply,
             socket
             |> assign(:messages, socket.assigns.messages ++ [user_msg, assistant_msg])
             |> assign(:query, "")
             |> assign(:loading, false)}

          {:error, _reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to get response")
             |> assign(:loading, false)
             |> assign(:messages, socket.assigns.messages ++ [user_msg])}
        end

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to process query")
         |> assign(:loading, false)
         |> assign(:messages, socket.assigns.messages ++ [user_msg])}
    end
  end

  @impl true
  def handle_event("submit", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:chat}>
      <div class="max-w-4xl mx-auto py-8 px-4 h-[calc(100vh-4rem)] flex flex-col">
        <h1 class="text-2xl font-bold mb-2">Document Chat</h1>
        <p class="text-gray-700 mb-6">Ask questions about your archived documents</p>
          <div :if={@messages == []} class="flex items-center justify-center h-full">
            <div class="text-center text-gray-500">
              <.icon name="hero-chat-bubble-left-right" class="w-16 h-16 mx-auto mb-4 text-gray-400" />
              <p class="text-lg text-gray-700">Ask a question about your documents</p>
            </div>
          </div>

          <div :for={msg <- @messages} class={"flex #{if msg.role == :user, do: "justify-end", else: "justify-start"}"}>
            <div :if={msg.role == :user} class="max-w-[70%] bg-blue-600 text-white rounded-2xl px-4 py-3">
              <p class="text-sm">{msg.content}</p>
            </div>

            <div :if={msg.role == :assistant} class="max-w-[80%]">
              <div class="bg-white border rounded-2xl px-4 py-3">
                <p class="text-sm text-gray-800">{msg.content}</p>
              </div>
              <div :if={msg.sources && msg.sources != []} class="mt-2 px-2">
                <p class="text-xs text-gray-500 mb-1">Sources:</p>
                <div :for={source <- msg.sources} class="flex items-center gap-1 mb-1">
                  <span class="text-xs text-blue-600 truncate">
                    {source.document.title || source.document.file_name}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div :if={@loading} class="flex justify-start">
            <div class="bg-white border rounded-2xl px-4 py-3">
              <div class="flex gap-1">
                <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
              </div>
            </div>
          </div>

        <form id="chat-form" phx-submit="submit" class="flex gap-3">
          <input
            id="query-input"
            type="text"
            name="query"
            value={@query}
            placeholder="Ask a question about your documents..."
            class="flex-1 px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-blue-500 focus:outline-none"
          />
          <button
            type="submit"
            disabled={@loading}
            class="px-6 py-3 bg-blue-600 text-white rounded-xl font-medium hover:bg-blue-700 transition-colors disabled:opacity-50"
          >
            Ask
          </button>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
