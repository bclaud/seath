defmodule Seath.OCR.Mock do
  @moduledoc """
  Mock OCR provider for development and testing.
  """
  @behaviour Seath.OCR.Provider

  @impl true
  def extract(_file_path), do: {:ok, "Mock extracted text from document."}
end
