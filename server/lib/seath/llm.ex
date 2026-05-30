defmodule Seath.LLM do
  @moduledoc """
  LLM context — delegates to the configured LLM provider for classification
  and to the configured chat provider for conversational responses.

  Supports two independent providers:
    - **LLM provider** (`:llm_provider`): used for classify/3 and embed/1
    - **Chat provider** (`:chat_provider`): used for chat/2, chat_stream/3,
      chat_with_tools/3

  Configure via `config :seath` or the Settings UI.
  The chat provider defaults to the LLM provider if not explicitly set.
  Available providers:
    - Seath.LLM.Ollama
    - Seath.LLM.OpenAI
  """

  @doc """
  Returns the configured LLM provider module (for classify/embed), or `nil`.
  """
  def impl do
    Application.get_env(:seath, :llm_provider)
  end

  @doc """
  Returns the configured chat provider module (for chat/stream/tools), or `nil`.
  Falls back to the LLM provider if no chat-specific provider is configured.
  """
  def chat_impl do
    Application.get_env(:seath, :chat_provider) || impl()
  end

  @doc """
  Classifies document text using the configured LLM provider.

  See `c:Seath.LLM.Provider.classify/3` for details.
  Returns `{:error, :not_configured}` if no LLM provider is configured.
  """
  def classify(text, available_tags, available_types, opts \\ []) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.classify(text, available_tags, available_types, opts)
    end
  end

  @doc """
  Phase 1 of two-phase classification: think/reason about the document.

  Returns natural language reasoning with structured extractions.
  See `c:Seath.LLM.Provider.think/2` for details.
  Returns `{:error, :not_configured}` if no LLM provider is configured.
  """
  def think(text, opts \\ []) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.think(text, opts)
    end
  end

  @doc """
  Phase 2 of two-phase classification: classify from reasoning.

  Uses the thinking output and extracted entities to produce structured
  classification. See `c:Seath.LLM.Provider.classify_from_reasoning/4` for details.
  Returns `{:error, :not_configured}` if no LLM provider is configured.
  """
  def classify_from_reasoning(thinking, text, available_tags, available_types, opts \\ []) do
    case impl() do
      nil ->
        {:error, :not_configured}

      provider ->
        provider.classify_from_reasoning(thinking, text, available_tags, available_types, opts)
    end
  end

  @doc """
  Verifies a classification result against the original document text.

  Cross-checks entities mentioned in classification against the document text.
  Returns `{:ok, verification_result}` or `{:error, :not_configured}`.
  """
  def verify(classification, text) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.verify(classification, text)
    end
  end

  @doc """
  Generates an embedding vector using the configured LLM provider.

  See `c:Seath.LLM.Provider.embed/1` for details.
  Returns `{:error, :not_configured}` if no LLM provider is configured.
  """
  def embed(text) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.embed(text)
    end
  end

  @doc """
  Generates a conversational response using the configured chat provider.

  See `c:Seath.LLM.Provider.chat/2` for message format details.
  Returns `{:error, :not_configured}` if no chat provider is available.
  """
  def chat(messages, opts \\ []) do
    case chat_impl() do
      nil -> {:error, :not_configured}
      provider -> provider.chat(messages, opts)
    end
  end

  @doc """
  Streams a conversational response token-by-token via the chat provider.

  Sends `{:stream_token, token_string}` messages to the `stream_to` pid.
  See `c:Seath.LLM.Provider.chat_stream/3` for details.
  Returns `{:error, :not_configured}` if no chat provider is available.
  """
  def chat_stream(messages, opts \\ [], stream_to) do
    case chat_impl() do
      nil -> {:error, :not_configured}
      provider -> provider.chat_stream(messages, opts, stream_to)
    end
  end

  @doc """
  Generates a tool-assisted conversational response via the chat provider.

  See `c:Seath.LLM.Provider.chat_with_tools/3` for details.
  Returns `{:error, :not_configured}` if no chat provider is available,
  or `{:error, :not_supported}` if the provider doesn't implement it.
  """
  def chat_with_tools(messages, tools, opts \\ []) do
    case chat_impl() do
      nil ->
        {:error, :not_configured}

      provider ->
        if function_exported?(provider, :chat_with_tools, 3) do
          provider.chat_with_tools(messages, tools, opts)
        else
          {:error, :not_supported}
        end
    end
  end

  @doc """
  Performs vision-based OCR on image data using the configured chat provider.

  See `c:Seath.LLM.Provider.ocr_vision/2` for details.
  Returns `{:error, :not_configured}` if no chat provider is available
  or the provider does not support `ocr_vision/2`.
  """
  def ocr_vision(image_data, opts \\ []) do
    case chat_impl() do
      nil ->
        {:error, :not_configured}

      provider ->
        if function_exported?(provider, :ocr_vision, 2) do
          provider.ocr_vision(image_data, opts)
        else
          {:error, :not_supported}
        end
    end
  end
end
