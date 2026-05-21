defmodule SeathWeb.SettingsLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    ocr_provider = Application.get_env(:seath, :ocr_provider)
    llm_provider = Application.get_env(:seath, :llm_provider)
    azure_config = Application.get_env(:seath, Seath.OCR.Azure, [])
    ollama_ocr_config = Application.get_env(:seath, Seath.OCR.Ollama, [])
    ollama_llm_config = Application.get_env(:seath, Seath.LLM.Ollama, [])
    base_url = ollama_ocr_config[:base_url] || System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")
    ocr_model = ollama_ocr_config[:model] || System.get_env("OLLAMA_OCR_MODEL", "llava")
    llm_model = ollama_llm_config[:model] || System.get_env("OLLAMA_LLM_MODEL", "llama3.2")

    {:ok,
     socket
     |> assign(:ocr_provider, ocr_provider_name(ocr_provider))
     |> assign(:llm_provider, llm_provider_name(llm_provider))
     |> assign(:azure_endpoint, azure_config[:endpoint] || System.get_env("AZURE_DI_ENDPOINT", ""))
     |> assign(:azure_key, azure_config[:key] || System.get_env("AZURE_DI_KEY", ""))
     |> assign(:ollama_base_url, base_url)
     |> assign(:ollama_ocr_model, ocr_model)
     |> assign(:ollama_llm_model, llm_model)
             |> assign(:ollama_connected, false)
             |> assign(:ollama_model_available, nil)
             |> assign(:testing, false)
             |> assign(:tested, false)}
  end

  @impl true
  def handle_event("save", params, socket) do
    ocr = params["ocr_provider"]
    llm = params["llm_provider"]
    base_url = params["ollama_base_url"] || "http://localhost:11434"

    Application.delete_env(:seath, :ocr_provider)
    Application.delete_env(:seath, :llm_provider)

    case ocr do
      "azure" ->
        Application.put_env(:seath, :ocr_provider, Seath.OCR.Azure)
        Application.put_env(:seath, Seath.OCR.Azure,
          endpoint: params["azure_endpoint"],
          key: params["azure_key"]
        )
      "ollama" ->
        Application.put_env(:seath, :ocr_provider, Seath.OCR.Ollama)
        Application.put_env(:seath, Seath.OCR.Ollama,
          base_url: base_url,
          model: params["ollama_ocr_model"]
        )
      _ -> :ok
    end

    case llm do
      "ollama" ->
        Application.put_env(:seath, :llm_provider, Seath.LLM.Ollama)
        Application.put_env(:seath, Seath.LLM.Ollama,
          base_url: base_url,
          model: params["ollama_llm_model"]
        )
      _ -> :ok
    end

    {:noreply,
     socket
     |> assign(:ocr_provider, ocr)
     |> assign(:llm_provider, llm)
     |> assign(:azure_endpoint, params["azure_endpoint"] || "")
     |> assign(:azure_key, params["azure_key"] || "")
     |> assign(:ollama_base_url, base_url)
     |> assign(:ollama_ocr_model, params["ollama_ocr_model"] || "llava")
     |> assign(:ollama_llm_model, params["ollama_llm_model"] || "llama3.2")
     |> put_flash(:info, "Settings saved!")}
  end

  @impl true
  def handle_event("test_ollama", _params, socket) do
    base_url = socket.assigns.ollama_base_url
    ocr_model = socket.assigns.ollama_ocr_model
    llm_model = socket.assigns.ollama_llm_model

    {:noreply,
     socket
     |> assign(:testing, true)
     |> assign(:ollama_model_available, nil)
     |> assign(:tested, true)
     |> test_ollama_connection(base_url, ocr_model, llm_model)
     |> assign(:testing, false)}
  end

  defp test_ollama_connection(socket, base_url, ocr_model, llm_model) do
    # Test basic connectivity
    case Req.get("#{base_url}/api/tags", receive_timeout: 3000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        available = Enum.map(models, & &1["name"])
        ocr_ok = ocr_model in available
        llm_ok = llm_model in available

        missing = []
        missing = if ocr_ok, do: missing, else: missing ++ ["OCR: #{ocr_model}"]
        missing = if llm_model == ocr_model or llm_ok, do: missing, else: missing ++ ["LLM: #{llm_model}"]

        socket
        |> assign(:ollama_connected, true)
        |> assign(:ollama_model_available, %{ocr: ocr_ok, llm: llm_ok})
        |> put_flash(:info, case missing do
          [] -> "Connected! All models available."
          _ -> "Connected! But pull missing models: #{Enum.join(missing, ", ")}"
        end)

      {:ok, %{status: 200}} ->
        socket
        |> assign(:ollama_connected, true)
        |> put_flash(:info, "Connected to Ollama at #{base_url}")

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        socket
        |> assign(:ollama_connected, false)
        |> put_flash(:error, "Cannot connect to Ollama at #{base_url}. Is 'ollama serve' running?")

      {:error, reason} ->
        socket
        |> assign(:ollama_connected, false)
        |> put_flash(:error, "Connection failed: #{inspect(reason)}")
    end
  end

  defp ocr_provider_name(nil), do: ""
  defp ocr_provider_name(Seath.OCR.Azure), do: "azure"
  defp ocr_provider_name(Seath.OCR.Ollama), do: "ollama"
  defp ocr_provider_name(_), do: ""

  defp llm_provider_name(nil), do: ""
  defp llm_provider_name(Seath.LLM.Ollama), do: "ollama"
  defp llm_provider_name(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_page={:settings}>
      <div class="max-w-3xl mx-auto py-8 px-4">
        <h1 class="text-2xl font-bold mb-2">Settings</h1>
        <p class="text-gray-500 mb-8">Configure AI providers for OCR and document classification</p>

        <form phx-submit="save" class="space-y-8">
          <%!-- OCR Provider --%>
          <div class="bg-white rounded-xl border p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">OCR Provider</h2>
            <p class="text-sm text-gray-500 mb-4">
              OCR extracts text from uploaded documents (PDFs, images). Required for classification and search.
            </p>

            <div class="space-y-3">
              <label class="flex items-center gap-3 p-3 rounded-lg border has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer">
                <input type="radio" name="ocr_provider" value="" checked={@ocr_provider == ""} class="text-blue-600" />
                <div>
                  <p class="text-sm font-medium text-gray-900">None</p>
                  <p class="text-xs text-gray-500">Documents will not be OCR'd</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer">
                <input type="radio" name="ocr_provider" value="ollama" checked={@ocr_provider == "ollama"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-medium text-gray-900">Ollama (Local)</p>
                  <p class="text-xs text-gray-500">Self-hosted, runs on your machine. You need a vision model like <strong>llava</strong>.</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer">
                <input type="radio" name="ocr_provider" value="azure" checked={@ocr_provider == "azure"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-medium text-gray-900">Azure Document Intelligence (Cloud)</p>
                  <p class="text-xs text-gray-500">Microsoft's cloud OCR service. Requires an Azure subscription.</p>
                </div>
              </label>
            </div>

            <%!-- Azure config --%>
            <div :if={@ocr_provider == "azure"} class="mt-6 p-4 bg-gray-50 rounded-lg border space-y-4">
              <h3 class="text-sm font-semibold text-gray-700">Azure Configuration</h3>
              <div>
                <label class="block text-xs font-medium text-gray-700 mb-1">Endpoint URL</label>
                <input type="text" name="azure_endpoint" value={@azure_endpoint}
                  placeholder="https://your-resource.cognitiveservices.azure.com"
                  class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg" />
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-700 mb-1">API Key</label>
                <input type="password" name="azure_key" value={@azure_key}
                  class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg" />
              </div>
            </div>
          </div>

          <%!-- LLM Provider --%>
          <div class="bg-white rounded-xl border p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Classification & Chat Provider</h2>
            <p class="text-sm text-gray-500 mb-4">
              Used to classify documents (auto-tagging), generate embeddings for search, and power the RAG chat.
            </p>
            <div class="space-y-3">
              <label class="flex items-center gap-3 p-3 rounded-lg border has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer">
                <input type="radio" name="llm_provider" value="" checked={@llm_provider == ""} class="text-blue-600" />
                <div>
                  <p class="text-sm font-medium text-gray-900">None</p>
                  <p class="text-xs text-gray-500">Documents will not be classified; chat will be unavailable</p>
                </div>
              </label>
              <label class="flex items-center gap-3 p-3 rounded-lg border has-[:checked]:border-blue-500 has-[:checked]:bg-blue-50 cursor-pointer">
                <input type="radio" name="llm_provider" value="ollama" checked={@llm_provider == "ollama"} class="text-blue-600" />
                <div>
                  <p class="text-sm font-medium text-gray-900">Ollama (Local)</p>
                  <p class="text-xs text-gray-500">
                    Models: <strong>llama3.2</strong> (fast), <strong>llama3.1</strong> (quality), <strong>mistral</strong> (balance)
                  </p>
                </div>
              </label>
            </div>
          </div>

          <%!-- Ollama connection & models --%>
          <div class="bg-white rounded-xl border p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Ollama Configuration</h2>
            <p class="text-sm text-gray-500 mb-4">
              Configure Ollama if you selected it above. Click <strong>Test Connection</strong> to verify.
            </p>

            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Server URL</label>
                <input type="text" name="ollama_base_url" value={@ollama_base_url}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg" />
              </div>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">OCR Model</label>
                  <input type="text" name="ollama_ocr_model" value={@ollama_ocr_model}
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg font-mono" />
                  <p class="text-xs text-gray-400 mt-1">Vision model. Suggestions: <strong>llava</strong>, <strong>minicpm-v</strong></p>
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">LLM Model</label>
                  <input type="text" name="ollama_llm_model" value={@ollama_llm_model}
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg font-mono" />
                  <p class="text-xs text-gray-400 mt-1">For classification + chat. Suggestions: <strong>llama3.2</strong>, <strong>llama3.1</strong></p>
                </div>
              </div>

              <%!-- Test connection button and results --%>
              <div class="p-4 bg-gray-50 rounded-lg border">
                <div class="flex items-center gap-4">
                  <button
                    type="button"
                    phx-click="test_ollama"
                    disabled={@testing}
                    class="px-4 py-2 bg-gray-900 text-white rounded-lg text-sm font-medium hover:bg-gray-800 disabled:opacity-50 transition-colors"
                  >
                    {if @testing, do: "Testing...", else: "Test Connection"}
                  </button>

                  <div :if={@ollama_connected} class="flex items-center gap-2 text-sm text-green-700">
                    <span class="w-2 h-2 rounded-full bg-green-500" />
                    Connected
                  </div>
                  <div :if={@ollama_connected == false && @tested} class="flex items-center gap-2 text-sm text-red-700">
                    <span class="w-2 h-2 rounded-full bg-red-500" />
                    Not connected
                  </div>

                  <%!-- Model status badges --%>
                  <div :if={@ollama_model_available} class="flex items-center gap-3 ml-4">
                    <span class={[
                      "text-xs px-2 py-0.5 rounded-full",
                      @ollama_model_available.ocr && "bg-green-100 text-green-700",
                      !@ollama_model_available.ocr && "bg-red-100 text-red-700"
                    ]}>
                      OCR: {if @ollama_model_available.ocr, do: "available", else: "missing"}
                    </span>
                    <span class={[
                      "text-xs px-2 py-0.5 rounded-full",
                      @ollama_model_available.llm && "bg-green-100 text-green-700",
                      !@ollama_model_available.llm && "bg-red-100 text-red-700"
                    ]}>
                      LLM: {if @ollama_model_available.llm, do: "available", else: "missing"}
                    </span>
                  </div>
                </div>

                <p class="text-xs text-gray-400 mt-3">
                  Missing models? Run <code class="bg-gray-200 px-1 rounded">ollama pull &lt;model_name&gt;</code> in your terminal.
                  The app does not download models automatically — models are several GB each.
                </p>
              </div>
            </div>
          </div>

          <%!-- Submit --%>
          <div class="flex justify-end">
            <button type="submit" class="px-6 py-3 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 transition-colors">
              Save Settings
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
