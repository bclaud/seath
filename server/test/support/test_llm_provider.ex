defmodule Seath.TestLLMProvider do
  @moduledoc """
  Test LLM provider that returns a classification with specific tags and document type.
  """
  @behaviour Seath.LLM.Provider

  @impl true
  def classify(_text, _available_tags, _available_types) do
    {:ok,
     %{
       title: "Test Invoice",
       document_type: "invoice",
       tags: ["invoice", "finance"],
       confidence: 0.9
     }}
  end

  @impl true
  def embed(_text) do
    {:ok, Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)}
  end

  @impl true
  def chat(_messages, _opts) do
    {:ok,
     "Based on the provided documents, I can see that there are several archived documents available."}
  end

  @impl true
  def chat_stream(_messages, _opts, stream_to) do
    response =
      "Based on the provided documents, I can see that there are several archived documents available."

    send(stream_to, {:stream_token, response})
    {:ok, response}
  end

  @impl true
  def ocr_vision(_image_data, _opts) do
    {:ok,
     "Test Invoice\nAmount: $1,234.56\nInvoice #: INV-2024-001\nDate: 2024-01-15\nVendor: Acme Corp\nTax ID: 12.345.678/0001-90"}
  end
end
