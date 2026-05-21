defmodule Seath.Settings do
  @moduledoc """
  Persisted application settings (OCR/LLM provider configuration).

  Settings are stored in a single-row table. On startup, if settings exist,
  they are applied to Application.put_env for immediate effect.
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
          azure_endpoint: nil,
          azure_key: nil,
          ollama_base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"),
          ollama_ocr_model: System.get_env("OLLAMA_OCR_MODEL", "llava"),
          ollama_llm_model: System.get_env("OLLAMA_LLM_MODEL", "llama3.2")
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
  """
  def apply_to_env(settings) do
    # Clear existing provider configs
    Application.delete_env(:seath, :ocr_provider)
    Application.delete_env(:seath, :llm_provider)

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

      _ ->
        :ok
    end

    # Set LLM provider
    case settings.llm_provider do
      "ollama" ->
        Application.put_env(:seath, :llm_provider, Seath.LLM.Ollama)

        Application.put_env(:seath, Seath.LLM.Ollama,
          base_url: settings.ollama_base_url,
          model: settings.ollama_llm_model
        )

      _ ->
        :ok
    end
  end
end
