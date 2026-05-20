defmodule Seath.OCR do
  @moduledoc """
  OCR context — delegates to the configured OCR provider.
  """

  @doc """
  Returns the configured OCR provider module.
  """
  def impl do
    Application.get_env(:seath, :ocr_provider, Seath.OCR.Mock)
  end

  @doc """
  Extracts text from a file using the configured OCR provider.
  """
  def extract(file_path) do
    impl().extract(file_path)
  end
end
