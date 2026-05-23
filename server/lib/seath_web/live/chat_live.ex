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
    user_msg = %{role: :user, content: query}

    socket =
      socket
      |> assign(:loading, true)
      |> assign(:query, "")
      |> update(:messages, &(&1 ++ [user_msg]))

    # Start the tool-calling + streaming flow in a background task
    live_view_pid = self()
    messages = socket.assigns.messages

    Task.start(fn ->
      run_tool_calling_flow(messages, query, live_view_pid)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("submit", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:stream_token, token}, socket) do
    messages = socket.assigns.messages

    messages =
      case List.last(messages) do
        %{role: :assistant} = last ->
          List.replace_at(messages, length(messages) - 1, %{last | content: last.content <> token})

        _ ->
          messages ++ [%{role: :assistant, content: token, sources: []}]
      end

    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_info({:stream_complete, sources}, socket) do
    messages = socket.assigns.messages

    messages =
      case List.last(messages) do
        %{role: :assistant} = last ->
          List.replace_at(messages, length(messages) - 1, %{last | sources: sources})

        _ ->
          messages
      end

    {:noreply, assign(socket, :messages, messages) |> assign(:loading, false)}
  end

  @impl true
  def handle_info({:stream_error, reason}, socket) do
    socket =
      socket
      |> put_flash(:error, reason)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  defp run_tool_calling_flow(existing_messages, query, live_view_pid) do
    # Build the initial message list with system prompt + conversation history + new query
    messages = build_tool_messages(existing_messages, query)

    case Seath.LLM.chat_with_tools(messages, Seath.LLM.Tools.tools(), []) do
      {:ok, %{tool_calls: tool_calls}} when tool_calls != [] ->
        # LLM requested tool execution — run tools and generate final answer
        handle_tool_calls(messages, tool_calls, [], query, live_view_pid)

      {:ok, _response} ->
        # LLM answered without using tools, or returned empty tool_calls.
        # Don't trust the answer — search documents ourselves via fallback.
        run_fallback_flow(query, live_view_pid)

      {:error, _reason} ->
        # Provider doesn't support tools or error occurred — use fallback
        run_fallback_flow(query, live_view_pid)
    end
  end

  defp handle_tool_calls(messages, tool_calls, collected_sources, _query, live_view_pid) do
    # 1. Add the assistant's tool-calling response to message history
    assistant_msg = %{role: "assistant", content: "", tool_calls: tool_calls}
    messages_with_assistant = messages ++ [assistant_msg]

    # 2. Execute each tool and collect results + sources
    {tool_result_messages, all_sources} =
      Enum.reduce(tool_calls, {[], collected_sources}, fn call, {results, sources} ->
        {text, doc_sources} =
          case Seath.LLM.Tools.execute(
                 call.function.name,
                 parse_arguments(call.function.arguments)
               ) do
            {:ok, text, doc_sources} -> {text, doc_sources}
            other -> {"Error executing tool: #{inspect(other)}", []}
          end

        tool_msg = %{
          role: "tool",
          content: text,
          tool_call_id: call.id
        }

        {results ++ [tool_msg], sources ++ doc_sources}
      end)

    # 3. Send the full history back to the LLM for the final answer
    full_messages = messages_with_assistant ++ tool_result_messages

    # Try streaming first, fall back to non-streaming
    case Seath.LLM.chat_stream(full_messages, [], live_view_pid) do
      {:ok, _full_response} ->
        send(live_view_pid, {:stream_complete, Enum.uniq_by(all_sources, & &1.id)})

      {:error, _reason} ->
        case Seath.LLM.chat(full_messages, []) do
          {:ok, response} ->
            send(live_view_pid, {:stream_token, response})
            send(live_view_pid, {:stream_complete, Enum.uniq_by(all_sources, & &1.id)})

          {:error, _r} ->
            send(live_view_pid, {:stream_error, "Failed to get response after tool execution."})
        end
    end
  end

  defp run_fallback_flow(query, live_view_pid) do
    # Fall back to the original retrieve-then-answer approach
    {:ok, messages, sources} = build_chat_context(query)

    case Seath.LLM.chat_stream(messages, [], live_view_pid) do
      {:ok, _full_response} ->
        send(live_view_pid, {:stream_complete, sources})

      {:error, _reason} ->
        case Seath.LLM.chat(messages, []) do
          {:ok, response} ->
            send(live_view_pid, {:stream_token, response})
            send(live_view_pid, {:stream_complete, sources})

          {:error, _reason} ->
            send(live_view_pid, {:stream_error, "Failed to get response"})
        end
    end
  end

  defp build_tool_messages(existing_messages, _query) do
    # Build conversation history for tool-calling
    # Existing messages already have user/assistant roles with atom keys
    # Convert to string keys for LLM API compatibility
    history =
      Enum.map(existing_messages, fn msg ->
        %{role: Atom.to_string(msg.role), content: msg.content}
      end)

    system_msg = %{
      role: "system",
      content:
        "You are a document Q&A assistant with access to search tools. " <>
          "Think step by step: first analyze what the user is asking, " <>
          "then decide which search tool to use. " <>
          "After receiving search results, reason about which documents are relevant " <>
          "and explain your reasoning briefly. " <>
          "Always cite specific documents by title in your answer. " <>
          "If the search results don't contain the information needed, say so clearly."
    }

    [system_msg | history]
  end

  defp build_chat_context(query) do
    # Step 1: Try grep-based retrieval first (exact match for names, IDs, dates)
    grep_results =
      Seath.Retrieval.search(query, limit: 3, max_docs: 3, include_docs: true, status: "archived")

    grep_count = length(grep_results)

    # Step 2: Fall back to embedding similarity search if grep didn't return enough results
    embedding_results =
      if grep_count < 3 do
        case Seath.LLM.embed(query) do
          {:ok, query_embedding} ->
            Seath.Embeddings.similarity_search(query_embedding,
              limit: 3 - grep_count,
              min_score: 0.5
            )
            |> Enum.map(fn %{embedding: _e, document: doc, score: _} ->
              %{document_id: doc.id, document: doc, match_count: 0, matches: []}
            end)

          {:error, _reason} ->
            []
        end
      else
        []
      end

    # Merge results: grep results first (higher priority), embeddings as fallback
    all_results = grep_results ++ embedding_results

    {context_messages, context_docs} =
      case all_results do
        [] ->
          {[], []}

        _ ->
          context_parts =
            Enum.map(all_results, fn %{document: doc} ->
              text_snippet = String.slice(doc.ocr_text || "", 0, 1000)
              "--- Document: #{doc.title || doc.file_name} ---\n#{text_snippet}"
            end)

          {[
              %{
                role: "system",
                content:
                  "You are a document Q&A assistant. Think step by step. " <>
                    "Review the context documents, identify which ones are relevant to the question, " <>
                    "then answer based only on the provided context. " <>
                    "Cite specific documents by title in your answer. " <>
                    "If the context doesn't contain relevant information, say so clearly."
              },
              %{
                role: "user",
                content: """
                Context documents:
                #{Enum.join(context_parts, "\n\n")}

                Question: #{query}

                First, think about which documents are relevant. Then answer the question based only on the provided context. Cite specific documents by title. If the context doesn't contain relevant information, say so.
                """
             }
            ], Enum.map(all_results, & &1.document) |> Enum.reject(&is_nil/1)}
      end

    # If no context was found, fall back to a simple query without context
    messages =
      if context_messages == [] do
        [
          %{
            role: "system",
            content:
              "You are a document Q&A assistant. I searched the document archive but found no matching documents. " <>
                "Tell the user honestly that no documents were found matching their query. " <>
                "Suggest they try different search terms or check if the documents are archived."
          },
          %{role: "user", content: query}
        ]
      else
        context_messages
      end

    {:ok, messages, context_docs}
  end

  defp parse_arguments(arguments) when is_map(arguments), do: arguments

  defp parse_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  defp parse_arguments(_arguments), do: %{}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:chat}>
      <div class="max-w-4xl mx-auto py-8 px-4 h-[calc(100vh-4rem)] flex flex-col">
        <h1 class="text-2xl font-bold mb-2">Document Chat</h1>
        <p class="text-base-content/80 mb-6">Ask questions about your archived documents</p>

        <div class="flex-1 overflow-y-auto space-y-4 mb-6">
          <div :if={@messages == []} class="flex items-center justify-center h-full">
            <div class="text-center text-base-content/90">
              <.icon
                name="hero-chat-bubble-left-right"
                class="w-16 h-16 mx-auto mb-4 text-base-content/90"
              />
              <p class="text-lg text-base-content/80">Ask a question about your documents</p>
            </div>
          </div>

          <div
            :for={msg <- @messages}
            class={"flex #{if msg.role == :user, do: "justify-end", else: "justify-start"}"}
          >
            <div
              :if={msg.role == :user}
              class="max-w-[70%] bg-blue-600 text-white rounded-2xl px-4 py-3"
            >
              <p class="text-sm">{msg.content}</p>
            </div>

            <div :if={msg.role == :assistant} class="max-w-[80%]">
              <div class="bg-white border rounded-2xl px-4 py-3">
                <p class="text-sm text-base-content/90">{msg.content}</p>
              </div>
              <div :if={msg.sources && msg.sources != []} class="mt-2 px-2">
                <p class="text-xs text-base-content/90 mb-1">Sources:</p>
                <div :for={source <- msg.sources} class="flex items-center gap-1 mb-1">
                  <.link
                    navigate={"/documents/#{source.id}"}
                    class="text-xs text-blue-600 hover:text-blue-800 hover:underline truncate flex items-center gap-1"
                  >
                    <span class="truncate">{source.title || source.file_name}</span>
                    <span class="shrink-0">↗</span>
                  </.link>
                </div>
              </div>
            </div>
          </div>

          <div :if={@loading} class="flex justify-start">
            <div class="bg-white border rounded-2xl px-4 py-3">
              <div class="flex gap-2 items-center text-base-content/60 text-sm">
                <div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce [animation-delay:0ms]" />
                <div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce [animation-delay:150ms]" />
                <div class="w-2 h-2 bg-blue-600 rounded-full animate-bounce [animation-delay:300ms]" />
              </div>
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
