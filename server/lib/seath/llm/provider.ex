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
          correspondent: String.t() | nil,
          involved_parties: [map()]
        }

  @type thinking_result :: %{
          reasoning: String.t(),
          extracted_entities: [String.t()],
          extracted_amounts: [String.t()],
          extracted_dates: [String.t()],
          summary: String.t()
        }

  @type verification_result :: %{
          passed: boolean(),
          verified_fields: [String.t()],
          flagged_fields: [%{field: String.t(), reason: String.t()}]
        }

  @type chat_message :: %{role: String.t(), content: String.t()}

  @type tool :: %{
          required(:function) => %{
            required(:name) => String.t(),
            required(:description) => String.t(),
            required(:parameters) => map()
          }
        }

  @type tool_call :: %{
          id: String.t(),
          type: String.t(),
          function: %{name: String.t(), arguments: String.t()}
        }

  @type chat_with_tools_response :: %{
          content: String.t(),
          tool_calls: [tool_call()]
        }

  @callback classify(
              text :: String.t(),
              available_tags :: [String.t()],
              available_types :: [String.t()],
              opts :: keyword()
            ) ::
              {:ok, classification_result()} | {:error, term()}

  @doc """
  Two-phase classification: Phase 1 — think.
  Takes OCR text and returns natural language reasoning with structured extractions.
  """
  @callback think(
              text :: String.t(),
              opts :: keyword()
            ) :: {:ok, thinking_result()} | {:error, term()}

  @doc """
  Two-phase classification: Phase 2 — classify from reasoning.
  Takes the thinking output + OCR text + available tags/types + similar document context
  and produces the structured classification.
  """
  @callback classify_from_reasoning(
              thinking :: thinking_result(),
              text :: String.t(),
              available_tags :: [String.t()],
              available_types :: [String.t()],
              opts :: keyword()
            ) :: {:ok, classification_result()} | {:error, term()}

  @doc """
  Verifies a classification result against the original document text.
  Cross-checks that entities mentioned in the classification actually appear
  in the document text.
  """
  @callback verify(
              classification :: classification_result(),
              text :: String.t()
            ) :: {:ok, verification_result()} | {:error, term()}

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

  @doc """
  Performs vision-based OCR on image data using the LLM's vision model.

  Takes raw image bytes and returns extracted text with attention to
  structured data (amounts, dates, invoice numbers, tax IDs, etc.).
  """
  @callback ocr_vision(image_data :: binary(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Generates a conversational response with tool/function-calling support.

  Takes a list of messages and tool definitions. Returns either a plain text
  response or a list of tool calls for the LLM to request execution of.

  Messages follow OpenAI-style format. Tool definitions follow OpenAI's
  function-calling schema.
  """
  @callback chat_with_tools(
              messages :: [chat_message()],
              tools :: [tool()],
              opts :: keyword()
            ) :: {:ok, chat_with_tools_response()} | {:error, term()}

  @optional_callbacks ocr_vision: 2, chat_with_tools: 3
end
