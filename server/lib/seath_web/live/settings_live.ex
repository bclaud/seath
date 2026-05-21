defmodule SeathWeb.SettingsLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    s = Seath.Settings.get_or_default()
    has_db_settings? = not is_nil(Seath.Settings.get())

    {:ok,
     socket
     |> assign(:ocr_provider, s.ocr_provider || "")
     |> assign(:llm_provider, s.llm_provider || "")
     |> assign(:chat_provider, s.chat_provider || "")
     |> assign(:azure_endpoint, s.azure_endpoint || "")
     |> assign(:azure_key, s.azure_key || "")
     |> assign(:ollama_base_url, s.ollama_base_url || "http://localhost:11434")
     |> assign(:ollama_ocr_model, s.ollama_ocr_model || "llama3.2-vision")
     |> assign(:ollama_llm_model, s.ollama_llm_model || "gemma4")
     |> assign(:ollama_chat_model, s.ollama_chat_model || "gemma4")
     |> assign(:openai_api_key, s.openai_api_key || "")
     |> assign(:openai_model, s.openai_model || "gpt-4o")
     |> assign(:openai_base_url, s.openai_base_url || "https://api.openai.com/v1")
     |> assign(:ollama_connected, false)
     |> assign(:ollama_model_available, nil)
     |> assign(:testing, false)
     |> assign(:tested, false)
     |> assign(:has_db_settings, has_db_settings?)
     |> assign(
       :using_env_vars,
       is_nil(Seath.Settings.get()) &&
         (System.get_env("OCR_PROVIDER") != nil || System.get_env("LLM_PROVIDER") != nil)
     )}
  end

  # Track form changes live so Test Connection reads current values
  @impl true
  def handle_event("update", params, socket) do
    {:noreply,
     socket
     |> assign(:ocr_provider, params["ocr_provider"] || socket.assigns.ocr_provider)
     |> assign(:llm_provider, params["llm_provider"] || socket.assigns.llm_provider)
     |> assign(:chat_provider, params["chat_provider"] || socket.assigns.chat_provider)
     |> assign(:azure_endpoint, params["azure_endpoint"] || socket.assigns.azure_endpoint)
     |> assign(:azure_key, params["azure_key"] || socket.assigns.azure_key)
     |> assign(:ollama_base_url, params["ollama_base_url"] || socket.assigns.ollama_base_url)
     |> assign(:ollama_ocr_model, params["ollama_ocr_model"] || socket.assigns.ollama_ocr_model)
     |> assign(:ollama_llm_model, params["ollama_llm_model"] || socket.assigns.ollama_llm_model)
     |> assign(:ollama_chat_model, params["ollama_chat_model"] || socket.assigns.ollama_chat_model)
     |> assign(:openai_api_key, params["openai_api_key"] || socket.assigns.openai_api_key)
     |> assign(:openai_model, params["openai_model"] || socket.assigns.openai_model)
     |> assign(:openai_base_url, params["openai_base_url"] || socket.assigns.openai_base_url)}
  end

  @impl true
  def handle_event("save", params, socket) do
    attrs = %{
      ocr_provider: params["ocr_provider"] || "",
      llm_provider: params["llm_provider"] || "",
      chat_provider: params["chat_provider"] || "",
      azure_endpoint: params["azure_endpoint"] || "",
      azure_key: params["azure_key"] || "",
      ollama_base_url: params["ollama_base_url"] || "http://localhost:11434",
      ollama_ocr_model: params["ollama_ocr_model"] || "llama3.2-vision",
      ollama_llm_model: params["ollama_llm_model"] || "gemma4",
      ollama_chat_model: params["ollama_chat_model"] || "gemma4",
      openai_api_key: params["openai_api_key"] || "",
      openai_model: params["openai_model"] || "gpt-4o",
      openai_base_url: params["openai_base_url"] || "https://api.openai.com/v1"
    }

    case Seath.Settings.save(attrs) do
      {:ok, s} ->
        {:noreply,
         socket
         |> assign(:ocr_provider, s.ocr_provider || "")
         |> assign(:llm_provider, s.llm_provider || "")
         |> assign(:chat_provider, s.chat_provider || "")
         |> assign(:azure_endpoint, s.azure_endpoint || "")
         |> assign(:azure_key, s.azure_key || "")
         |> assign(:ollama_base_url, s.ollama_base_url || "http://localhost:11434")
         |> assign(:ollama_ocr_model, s.ollama_ocr_model || "llama3.2-vision")
         |> assign(:ollama_llm_model, s.ollama_llm_model || "gemma4")
         |> assign(:ollama_chat_model, s.ollama_chat_model || "gemma4")
         |> assign(:openai_api_key, s.openai_api_key || "")
         |> assign(:openai_model, s.openai_model || "gpt-4o")
         |> assign(:openai_base_url, s.openai_base_url || "https://api.openai.com/v1")
         |> assign(:has_db_settings, true)
         |> assign(:using_env_vars, false)
         |> put_flash(:info, "Settings saved! Env vars will no longer be used on restart.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  @impl true
  def handle_event("test_ollama", _params, socket) do
    base_url = socket.assigns.ollama_base_url
    ocr_model = socket.assigns.ollama_ocr_model
    llm_model = socket.assigns.ollama_llm_model
    chat_model = socket.assigns.ollama_chat_model

    {:noreply,
     socket
     |> assign(:testing, true)
     |> assign(:ollama_model_available, nil)
     |> assign(:tested, true)
     |> test_ollama_connection(base_url, ocr_model, llm_model, chat_model)
     |> assign(:testing, false)}
  end

  defp test_ollama_connection(socket, base_url, ocr_model, llm_model, chat_model) do
    case Req.get("#{base_url}/api/tags", receive_timeout: 3000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        available = Enum.map(models, fn m -> String.split(m["name"], ":") |> hd() end)
        ocr_ok = ocr_model in available
        llm_ok = llm_model in available
        chat_ok = chat_model in available

        missing = []
        missing = if ocr_ok, do: missing, else: missing ++ ["OCR: #{ocr_model}"]
        missing = if llm_ok, do: missing, else: missing ++ ["LLM: #{llm_model}"]
        missing = if chat_ok or chat_model == llm_model, do: missing, else: missing ++ ["Chat: #{chat_model}"]

        socket
        |> assign(:ollama_connected, true)
        |> assign(:ollama_model_available, %{ocr: ocr_ok, llm: llm_ok, chat: chat_ok})
        |> put_flash(
          :info,
          case missing do
            [] -> "Connected! All models available."
            _ -> "Connected! But pull missing models: #{Enum.join(missing, ", ")}"
          end
        )

      {:ok, %{status: 200}} ->
        socket
        |> assign(:ollama_connected, true)
        |> put_flash(:info, "Connected to Ollama at #{base_url}")

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        socket
        |> assign(:ollama_connected, false)
        |> put_flash(
          :error,
          "Cannot connect to Ollama at #{base_url}. Is 'ollama serve' running?"
        )

      {:error, reason} ->
        socket
        |> assign(:ollama_connected, false)
        |> put_flash(:error, "Connection failed: #{inspect(reason)}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:settings}>
      <div class="max-w-3xl mx-auto py-8 px-4">
        <h1 class="text-2xl font-bold text-base-content mb-2">Settings</h1>
        <p class="text-base-content/70 mb-8">
          Configure AI providers independently for OCR, document classification, and chat
        </p>

        <%!-- Config source banner --%>
        <div :if={@has_db_settings} class="mb-6 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <p class="text-sm text-blue-800">
            Settings are loaded from the database. Environment variables are ignored after first save.
          </p>
        </div>
        <div :if={@using_env_vars} class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
          <p class="text-sm text-yellow-800">
            Using environment variables. Save settings below to switch to database mode.
          </p>
        </div>

        <form phx-change="update" phx-submit="save" class="space-y-8">
          <%!-- OCR Provider --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-3">OCR Provider</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Extracts text from uploaded documents (PDFs, images). Required for classification and search.
            </p>
            <div class="space-y-3">
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="ocr_provider" value="" checked={@ocr_provider == ""} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">None</p>
                  <p class="text-xs text-base-content/70">Documents will not be OCR'd</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="ocr_provider" value="ollama" checked={@ocr_provider == "ollama"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">Ollama &mdash; Local</p>
                  <p class="text-xs text-base-content/70">Vision model. Recommended: <strong>llama3.2-vision</strong></p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="ocr_provider" value="azure" checked={@ocr_provider == "azure"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">Azure Document Intelligence</p>
                  <p class="text-xs text-base-content/70">Microsoft's cloud OCR. Requires an Azure subscription.</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="ocr_provider" value="openai" checked={@ocr_provider == "openai"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">OpenAI &mdash; Cloud</p>
                  <p class="text-xs text-base-content/70">GPT-4o vision. Requires an API key.</p>
                </div>
              </label>
            </div>
            <div :if={@ocr_provider == "azure"} class="mt-6 p-4 bg-gray-50 rounded-lg border border-gray-200 space-y-4">
              <h3 class="text-sm font-semibold text-base-content">Azure Configuration</h3>
              <div>
                <label class="block text-sm font-medium text-base-content/90 mb-1">Endpoint URL</label>
                <input type="text" name="azure_endpoint" value={@azure_endpoint} placeholder="https://your-resource.cognitiveservices.azure.com" class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content" />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content/90 mb-1">API Key</label>
                <input type="password" name="azure_key" value={@azure_key} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content" />
              </div>
            </div>
          </div>

          <%!-- LLM Provider (Classification) --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-3">Classification Provider (LLM)</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Classifies documents (auto-tagging, type, correspondent). Can use a different model/provider than chat.
            </p>
            <div class="space-y-3">
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="llm_provider" value="" checked={@llm_provider == ""} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">None</p>
                  <p class="text-xs text-base-content/70">Documents will not be classified</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="llm_provider" value="ollama" checked={@llm_provider == "ollama"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">Ollama &mdash; Local</p>
                  <p class="text-xs text-base-content/70">Recommended: <strong>gemma4</strong></p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="llm_provider" value="openai" checked={@llm_provider == "openai"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">OpenAI &mdash; Cloud</p>
                  <p class="text-xs text-base-content/70">Requires API key. <strong>gpt-4o</strong> recommended.</p>
                </div>
              </label>
            </div>
          </div>

          <%!-- Chat Provider --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-3">Chat Provider</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Powers the RAG chat with tool-use (search + answer). Can use a different provider than classification.
              Leave as "Same as Classification" to reuse the LLM provider above.
            </p>
            <div class="space-y-3">
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="chat_provider" value="" checked={@chat_provider == ""} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">Same as Classification</p>
                  <p class="text-xs text-base-content/70">Uses the same provider and model as selected above</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="chat_provider" value="ollama" checked={@chat_provider == "ollama"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">Ollama &mdash; Local</p>
                  <p class="text-xs text-base-content/70">Separate Ollama model for chat. Recommended: <strong>gemma4</strong></p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border border-gray-200 has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer hover:bg-gray-50 transition-colors">
                <input type="radio" name="chat_provider" value="openai" checked={@chat_provider == "openai"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-semibold text-base-content">OpenAI &mdash; Cloud</p>
                  <p class="text-xs text-base-content/70">Best tool-use/function-calling. <strong>gpt-4o</strong> recommended.</p>
                </div>
              </label>
            </div>
          </div>

          <%!-- Ollama Connection & Models --%>
          <div class="bg-white rounded-xl border border-gray-200 p-6">
            <h2 class="text-lg font-semibold text-base-content mb-3">Ollama Configuration</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Configure Ollama if you selected it above. Click <strong>Test Connection</strong> to verify.
            </p>

            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-base-content/90 mb-1">Server URL</label>
                <input type="text" name="ollama_base_url" value={@ollama_base_url} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content" />
              </div>

              <div class="grid grid-cols-3 gap-4">
                <div>
                  <label class="block text-sm font-medium text-base-content/90 mb-1">OCR Model</label>
                  <input type="text" name="ollama_ocr_model" value={@ollama_ocr_model} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content font-mono" />
                  <p class="text-xs text-base-content/70 mt-1">Vision model. <strong>llama3.2-vision</strong></p>
                </div>
                <div>
                  <label class="block text-sm font-medium text-base-content/90 mb-1">LLM Model</label>
                  <input type="text" name="ollama_llm_model" value={@ollama_llm_model} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content font-mono" />
                  <p class="text-xs text-base-content/70 mt-1">Classification. <strong>gemma4</strong></p>
                </div>
                <div>
                  <label class="block text-sm font-medium text-base-content/90 mb-1">Chat Model</label>
                  <input type="text" name="ollama_chat_model" value={@ollama_chat_model} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content font-mono" />
                  <p class="text-xs text-base-content/70 mt-1">Tool-use. <strong>gemma4</strong></p>
                </div>
              </div>

              <%!-- OpenAI Configuration (shown when any OpenAI is selected) --%>
              <div :if={@llm_provider == "openai" || @chat_provider == "openai" || @ocr_provider == "openai"} class="p-4 bg-gray-50 rounded-lg border border-gray-200 space-y-4">
                <h3 class="text-sm font-semibold text-base-content">OpenAI Configuration</h3>
                <div>
                  <label class="block text-sm font-medium text-base-content/90 mb-1">API Key</label>
                  <input type="password" name="openai_api_key" value={@openai_api_key} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content" />
                </div>
                <div class="grid grid-cols-2 gap-4">
                  <div>
                    <label class="block text-sm font-medium text-base-content/90 mb-1">Model</label>
                    <input type="text" name="openai_model" value={@openai_model} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content font-mono" />
                    <p class="text-xs text-base-content/70 mt-1"><strong>gpt-4o</strong> for tools + vision</p>
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-base-content/90 mb-1">Base URL</label>
                    <input type="text" name="openai_base_url" value={@openai_base_url} class="w-full px-3 py-2 border border-gray-300 rounded-lg text-base-content font-mono" />
                    <p class="text-xs text-base-content/70 mt-1">For OpenAI-compatible APIs</p>
                  </div>
                </div>
              </div>

              <%!-- Test connection area --%>
              <div class="p-4 bg-gray-50 rounded-lg border border-gray-200">
                <div class="flex items-center gap-4">
                  <button type="button" phx-click="test_ollama" disabled={@testing} class="px-4 py-2 bg-gray-900 text-white rounded-lg text-sm font-semibold hover:bg-gray-800 disabled:opacity-50 transition-colors">
                    {if @testing, do: "Testing...", else: "Test Connection"}
                  </button>
                  <div :if={@ollama_connected && @tested} class="flex items-center gap-2 text-sm font-medium text-green-700">
                    <span class="w-2.5 h-2.5 rounded-full bg-green-500" /> Connected
                  </div>
                  <div :if={!@ollama_connected && @tested} class="flex items-center gap-2 text-sm font-medium text-red-700">
                    <span class="w-2.5 h-2.5 rounded-full bg-red-500" /> Not connected
                  </div>
                  <div :if={@ollama_model_available} class="flex items-center gap-3 ml-4">
                    <span class={["text-xs px-2.5 py-1 rounded-full font-medium", @ollama_model_available.ocr && "bg-green-100 text-green-800", !@ollama_model_available.ocr && "bg-red-100 text-red-800"]}>
                      OCR: {if @ollama_model_available.ocr, do: "✓", else: "✗"}
                    </span>
                    <span class={["text-xs px-2.5 py-1 rounded-full font-medium", @ollama_model_available.llm && "bg-green-100 text-green-800", !@ollama_model_available.llm && "bg-red-100 text-red-800"]}>
                      LLM: {if @ollama_model_available.llm, do: "✓", else: "✗"}
                    </span>
                    <span class={["text-xs px-2.5 py-1 rounded-full font-medium", @ollama_model_available.chat && "bg-green-100 text-green-800", !@ollama_model_available.chat && "bg-red-100 text-red-800"]}>
                      Chat: {if @ollama_model_available.chat, do: "✓", else: "✗"}
                    </span>
                  </div>
                </div>
                <p class="text-xs text-base-content/70 mt-3">
                  Missing models? Run <code class="bg-gray-200 text-base-content/90 px-1 rounded">ollama pull &lt;model_name&gt;</code> in your terminal.
                </p>
              </div>
            </div>
          </div>

          <%!-- Submit --%>
          <div class="flex justify-end">
            <button type="submit" class="px-6 py-3 bg-blue-600 text-white rounded-lg font-semibold hover:bg-blue-700 transition-colors">
              Save Settings
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end

end
