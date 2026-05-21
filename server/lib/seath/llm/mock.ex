defmodule Seath.LLM.Mock do
  @moduledoc """
  Mock LLM provider for development and testing.
  """
  @behaviour Seath.LLM.Provider

  @impl true
  def classify(_text, _available_tags, _available_types) do
    {:ok,
     %{
       title: "Untitled Document",
       document_type: nil,
       tags: [],
       confidence: 0.5
     }}
  end

  @impl true
  def embed(_text), do: {:ok, Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)}

  @impl true
  def chat(_messages, _opts) do
    {:ok, "This is a mock chat response. I don't have access to your documents in mock mode."}
  end

  @impl true
  def chat_stream(_messages, opts, stream_to) do
    # Simulate streaming by sending the full response as a single stream token
    response =
      Keyword.get(opts, :response, "This is a mock streaming response.")

    send(stream_to, {:stream_token, response})
    {:ok, response}
  end

  @impl true
  def ocr_vision(_image_data, _opts) do
    {:ok,
     "Mock OCR text extracted via vision LLM.\n\nAmount: $1,234.56\nInvoice #: INV-2024-001\nDate: 2024-01-15\nTax ID: 12.345.678/0001-90"}
  end
end
