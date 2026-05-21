defmodule SeathWeb.SettingsLive do
  use SeathWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    ocr_provider = Application.get_env(:seath, :ocr_provider)
    llm_provider = Application.get_env(:seath, :llm_provider)
    azure_config = Application.get_env(:seath, Seath.OCR.Azure, [])
    ollama_ocr_config = Application.get_env(:seath, Seath.OCR.Ollama, [])
    ollama_llm_config = Application.get_env(:seath, Seath.LLM.Ollama, [])
    ollama_available = check_ollama(ollama_ocr_config[:base_url] || "http://localhost:11434")

    {:ok,
     socket
     |> assign(:ocr_provider, ocr_provider_name(ocr_provider))
     |> assign(:llm_provider, llm_provider_name(llm_provider))
     |> assign(:azure_endpoint, azure_config[:endpoint] || System.get_env("AZURE_DI_ENDPOINT", ""))
     |> assign(:azure_key, azure_config[:key] || System.get_env("AZURE_DI_KEY", ""))
     |> assign(:ollama_base_url, ollama_ocr_config[:base_url] || System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"))
     |> assign(:ollama_ocr_model, ollama_ocr_config[:model] || System.get_env("OLLAMA_OCR_MODEL", "llava"))
     |> assign(:ollama_llm_model, ollama_llm_config[:model] || System.get_env("OLLAMA_LLM_MODEL", "llama3.2"))
     |> assign(:ollama_status, if(ollama_available, do: "connected", else: "disconnected"))
     |> assign(:saved, false)}
  end

  @impl true
  def handle_event("save", params, socket) do
    ocr_provider = params["ocr_provider"]
    llm_provider = params["llm_provider"]

    # Clear all provider configs first
    Application.delete_env(:seath, :ocr_provider)
    Application.delete_env(:seath, :llm_provider)

    # Set OCR provider
    case ocr_provider do
      "azure" ->
        Application.put_env(:seath, :ocr_provider, Seath.OCR.Azure)
        Application.put_env(:seath, Seath.OCR.Azure,
          endpoint: params["azure_endpoint"],
          key: params["azure_key"]
        )

      "ollama" ->
        Application.put_env(:seath, :ocr_provider, Seath.OCR.Ollama)
        Application.put_env(:seath, Seath.OCR.Ollama,
          base_url: params["ollama_base_url"],
          model: params["ollama_ocr_model"]
        )

      _ ->
        :ok
    end

    # Set LLM provider
    case llm_provider do
      "ollama" ->
        Application.put_env(:seath, :llm_provider, Seath.LLM.Ollama)
        Application.put_env(:seath, Seath.LLM.Ollama,
          base_url: params["ollama_base_url"],
          model: params["ollama_llm_model"]
        )

      _ ->
        :ok
    end

    {:noreply,
     socket
     |> assign(:ocr_provider, ocr_provider)
     |> assign(:llm_provider, llm_provider)
     |> assign(:azure_endpoint, params["azure_endpoint"] || "")
     |> assign(:azure_key, params["azure_key"] || "")
     |> assign(:ollama_base_url, params["ollama_base_url"] || "http://localhost:11434")
     |> assign(:ollama_ocr_model, params["ollama_ocr_model"] || "llava")
     |> assign(:ollama_llm_model, params["ollama_llm_model"] || "llama3.2")
     |> assign(:saved, true)
     |> put_flash(:info, "Settings saved!")}
  end

  @impl true
  def handle_event("test_ollama", _params, socket) do
    base_url = socket.assigns.ollama_base_url
    available = check_ollama(base_url)

    {:noreply,
     socket
     |> assign(:ollama_status, if(available, do: "connected", else: "disconnected"))
     |> put_flash(if(available, do: :info, else: :error),
        if(available, do: "Ollama is reachable at #{base_url}", else: "Could not connect to Ollama at #{base_url}")
      )}
  end

  defp check_ollama(base_url) do
    case Req.get("#{base_url}/api/tags", receive_timeout: 2000) do
      {:ok, %{status: 200}} -> true
      _ -> false
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

        <form phx-change="save" class="space-y-8">
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
                  <p class="text-xs text-gray-500">Self-hosted, runs on your machine. Recommended: <strong>llava</strong> or <strong>minicpm-v</strong></p>
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

            <%!-- Ollama OCR config --%>
            <div :if={@ocr_provider == "ollama" || @llm_provider == "ollama"} class="mt-6 p-4 bg-gray-50 rounded-lg border space-y-4">
              <h3 class="text-sm font-semibold text-gray-700">Ollama Connection</h3>
              <div class="flex items-center gap-2 mb-3">
                <span class={[
                  "inline-block w-2 h-2 rounded-full",
                  @ollama_status == "connected" && "bg-green-500",
                  @ollama_status != "connected" && "bg-red-500"
                ]} />
                <span class="text-xs text-gray-500">
                  {@ollama_status == "connected" && "Connected"}
                  {@ollama_status != "connected" && "Not connected"}
                </span>
                <button
                  type="button"
                  phx-click="test_ollama"
                  class="text-xs text-blue-600 hover:text-blue-800 underline ml-2"
                >
                  Test connection
                </button>
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-700 mb-1">Base URL</label>
                <input type="text" name="ollama_base_url" value={@ollama_base_url}
                  class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg" />
              </div>
              <div :if={@ocr_provider == "ollama"}>
                <label class="block text-xs font-medium text-gray-700 mb-1">
                  OCR Model
                  <span class="text-gray-400 font-normal ml-1">— vision model for text extraction. Recommended: <strong>llava</strong>, <strong>minicpm-v</strong>, <strong>llama3.2-vision</strong></span>
                </label>
                <input type="text" name="ollama_ocr_model" value={@ollama_ocr_model}
                  class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg font-mono" />
              </div>
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
                    Recommended models:
                    <strong>llama3.2</strong> (fast, good classification),
                    <strong>llama3.1</strong> (better quality, slower),
                    <strong>mistral</strong> (good balance)
                  </p>
                </div>
              </label>
            </div>

            <div :if={@llm_provider == "ollama"} class="mt-6 p-4 bg-gray-50 rounded-lg border">
              <label class="block text-xs font-medium text-gray-700 mb-1">LLM Model</label>
              <input type="text" name="ollama_llm_model" value={@ollama_llm_model}
                class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg font-mono" />
              <p class="text-xs text-gray-400 mt-1">
                For classification + chat. Runs on the same Ollama server configured above.
              </p>
            </div>
          </div>

          <div class="flex justify-end">
            <button
              type="submit"
              class="px-6 py-3 bg-blue-600 text-white rounded-lg font-medium hover:bg-blue-700 transition-colors"
            >
              Save Settings
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
