defmodule Seath.OCR do
  @moduledoc """
  OCR context — delegates to the configured OCR provider.

  Configure via `config :seath, :ocr_provider, Seath.OCR.Azure`
  or set the `OCR_PROVIDER` env var. Available providers:
    - Seath.OCR.Azure
    - Seath.OCR.Ollama
  """

  @doc """
  Returns the configured OCR provider module, or `nil` if none is configured.
  """
  def impl do
    Application.get_env(:seath, :ocr_provider)
  end

  @doc """
  Extracts text from a file using the configured OCR provider.

  Returns `{:error, :not_configured}` if no OCR provider is configured.
  """
  def extract(file_path) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.extract(file_path)
    end
  end
end
