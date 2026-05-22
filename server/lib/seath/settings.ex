defmodule Seath.Settings do
  @moduledoc """
  Persisted application settings (OCR/LLM/Chat provider configuration).

  Settings are stored in a single-row table. On startup, if settings exist,
  they are applied to Application.put_env for immediate effect.

  Supports three independent providers:
    - OCR: extracts text from documents (Azure, Ollama, OpenAI)
    - LLM: classifies documents and generates embeddings (Ollama, OpenAI)
    - Chat: powers RAG chat with tool-use (Ollama, OpenAI)
  """

  alias Seath.Repo

  @fixed_id "00000000-0000-0000-0000-000000000001"

  @doc """
  Returns the current settings, or `nil` if none saved.
  """
  def get do
    Repo.get(Seath.Settings.Setting, @fixed_id)
  end

  @doc """
  Returns the current settings, creating defaults if none exist.
  """
  def get_or_default do
    case get() do
      nil ->
        %Seath.Settings.Setting{
          ocr_provider: "",
          llm_provider: "",
          chat_provider: "",
          azure_endpoint: nil,
          azure_key: nil,
          ollama_base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"),
          ollama_ocr_model: System.get_env("OLLAMA_OCR_MODEL", "llama3.2-vision"),
          ollama_llm_model: System.get_env("OLLAMA_LLM_MODEL", "gemma4"),
          ollama_chat_model: System.get_env("OLLAMA_CHAT_MODEL", "gemma4"),
          openai_api_key: nil,
          openai_model: System.get_env("OPENAI_LLM_MODEL", "gpt-4o"),
          openai_base_url: System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
        }

      settings ->
        settings
    end
  end

  @doc """
  Saves settings and applies them to the runtime environment immediately.
  """
  def save(attrs) do
    result =
      case get() do
        nil ->
          %Seath.Settings.Setting{id: @fixed_id}
          |> Seath.Settings.Setting.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> Seath.Settings.Setting.changeset(attrs)
          |> Repo.update()
      end

    with {:ok, settings} <- result do
      apply_to_env(settings)
    end

    result
  end

  @doc """
  Loads settings from DB and applies them to the runtime environment.
  Called on application startup.
  """
  def load_and_apply do
    case get() do
      nil ->
        :no_settings

      settings ->
        apply_to_env(settings)
        :ok
    end
  end

  @doc """
  Applies the given settings to Application.put_env for immediate effect.

  Sets three independent providers:
    - :ocr_provider  → used by Seath.OCR.extract/1
    - :llm_provider  → used by Seath.LLM.classify/3, Seath.LLM.think/2,
                       Seath.LLM.classify_from_reasoning/5, Seath.LLM.verify/2,
                       Seath.LLM.embed/1
    - :chat_provider → used by Seath.LLM.chat/2, Seath.LLM.chat_stream/3,
                       Seath.LLM.chat_with_tools/3
  """
  def apply_to_env(settings) do
    # Clear existing provider configs
    Application.delete_env(:seath, :ocr_provider)
    Application.delete_env(:seath, :llm_provider)
    Application.delete_env(:seath, :chat_provider)

    # Set OCR provider
    case settings.ocr_provider do
      "azure" ->
        Application.put_env(:seath, :ocr_provider, Seath.OCR.Azure)

        Application.put_env(:seath, Seath.OCR.Azure,
          endpoint: settings.azure_endpoint,
          key: settings.azure_key
        )

      "ollama" ->
        Application.put_env(:seath, :ocr_provider, Seath.OCR.Ollama)

        Application.put_env(:seath, Seath.OCR.Ollama,
          base_url: settings.ollama_base_url,
          model: settings.ollama_ocr_model
        )

      "openai" ->
        Application.put_env(:seath, :ocr_provider, Seath.LLM.OpenAI)

        Application.put_env(:seath, Seath.LLM.OpenAI,
          api_key: settings.openai_api_key,
          base_url: settings.openai_base_url,
          model: settings.openai_model
        )

      _ ->
        :ok
    end

    # Shared Ollama config for providers that use it
    maybe_put_ollama(settings)
    maybe_put_openai(settings)

    # Set LLM provider (classification + embeddings)
    case settings.llm_provider do
      "ollama" ->
        Application.put_env(:seath, :llm_provider, Seath.LLM.Ollama)

        Application.put_env(:seath, Seath.LLM.Ollama,
          base_url: settings.ollama_base_url,
          model: settings.ollama_llm_model
        )

      "openai" ->
        Application.put_env(:seath, :llm_provider, Seath.LLM.OpenAI)

        Application.put_env(:seath, Seath.LLM.OpenAI,
          api_key: settings.openai_api_key,
          base_url: settings.openai_base_url,
          model: settings.openai_model
        )

      _ ->
        :ok
    end

    # Set Chat provider (conversation + tool-use) — defaults to LLM provider if not set
    chat_provider =
      case settings.chat_provider do
        "" -> settings.llm_provider
        p -> p
      end

    case chat_provider do
      "ollama" ->
        Application.put_env(:seath, :chat_provider, Seath.LLM.Ollama)

        Application.put_env(:seath, Seath.LLM.Ollama,
          base_url: settings.ollama_base_url,
          model: settings.ollama_chat_model
        )

      "openai" ->
        Application.put_env(:seath, :chat_provider, Seath.LLM.OpenAI)

        Application.put_env(:seath, Seath.LLM.OpenAI,
          api_key: settings.openai_api_key,
          base_url: settings.openai_base_url,
          model: settings.openai_model
        )

      _ ->
        :ok
    end
  end

  defp maybe_put_ollama(settings) do
    if settings.ollama_base_url do
      existing = Application.get_env(:seath, Seath.LLM.Ollama, [])
      Application.put_env(:seath, Seath.LLM.Ollama,
        Keyword.merge(existing, base_url: settings.ollama_base_url)
      )
    end
  end

  defp maybe_put_openai(settings) do
    if settings.openai_api_key && settings.openai_api_key != "" do
      existing = Application.get_env(:seath, Seath.LLM.OpenAI, [])
      Application.put_env(:seath, Seath.LLM.OpenAI,
        Keyword.merge(existing,
          api_key: settings.openai_api_key,
          base_url: settings.openai_base_url || "https://api.openai.com/v1"
        )
      )
    end
  end
end
