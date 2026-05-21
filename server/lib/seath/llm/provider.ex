defmodule Seath.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  Implementations must classify document text, generate embeddings,
  and provide conversational chat responses.
  """

  @type classification_result :: %{
          title: String.t(),
          document_type: String.t() | nil,
          tags: [String.t()],
          confidence: float()
        }

  @type chat_message :: %{role: String.t(), content: String.t()}

  @callback classify(
              text :: String.t(),
              available_tags :: [String.t()],
              available_types :: [String.t()]
            ) ::
              {:ok, classification_result()} | {:error, term()}

  @callback embed(text :: String.t()) :: {:ok, [float()]} | {:error, term()}

  @doc """
  Generates a conversational response for the given messages.

  Messages follow OpenAI-style format: `[%{role: "user"|"assistant"|"system", content: String.t()}]`.
  Returns the full response text on success.
  """
  @callback chat(
              messages :: [chat_message()],
              opts :: keyword()
            ) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Streams a conversational response token-by-token.

  Sends `{:token, token_string}` messages to the `stream_to` pid as tokens are received,
  then returns `{:ok, full_response}` when complete.
  """
  @callback chat_stream(
              messages :: [chat_message()],
              opts :: keyword(),
              stream_to :: pid()
            ) :: {:ok, String.t()} | {:error, term()}
end
