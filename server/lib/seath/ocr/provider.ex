defmodule Seath.OCR.Provider do
  @moduledoc """
  Behaviour for OCR providers.

  Implementations must return extracted text from a file path.
  """

  @callback extract(file_path :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
