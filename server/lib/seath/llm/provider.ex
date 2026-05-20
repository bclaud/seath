defmodule Seath.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  Implementations must classify document text and return structured metadata.
  """

  @type classification_result :: %{
          title: String.t(),
          document_type: String.t() | nil,
          tags: [String.t()],
          confidence: float()
        }

  @callback classify(
              text :: String.t(),
              available_tags :: [String.t()],
              available_types :: [String.t()]
            ) ::
              {:ok, classification_result()} | {:error, term()}

  @callback embed(text :: String.t()) :: {:ok, [float()]} | {:error, term()}
end
