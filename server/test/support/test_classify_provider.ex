defmodule Seath.TestClassifyProvider do
  @moduledoc """
  Test provider for the multi-step classify module that returns valid JSON responses
  for each classification prompt type.
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
  def embed(_text), do: {:ok, Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)}

  @impl true
  def chat(messages, _opts) do
    content = List.last(messages)[:content] || ""

    cond do
      # Metadata extraction prompt
      String.contains?(content, "extract metadata") ->
        {:ok, ~s({"title": "Invoice #1234", "document_type": "invoice", "confidence": 0.95})}

      # Tags extraction prompt
      String.contains?(content, "Select the most relevant tags") ->
        {:ok, ~s(["invoice", "finance", "acme"])}

      # Correspondent extraction prompt
      String.contains?(content, "Suggest a correspondent") ->
        {:ok, "Acme Corporation"}

      # Involved parties extraction prompt
      String.contains?(content, "named entities") ->
        {:ok,
         ~s([{"name": "Acme Corp", "role": "sender"}, {"name": "John Doe", "role": "recipient"}])}

      true ->
        {:ok, "Mock response"}
    end
  end

  @impl true
  def chat_stream(_messages, _opts, stream_to) do
    response = "Mock streaming response."
    send(stream_to, {:stream_token, response})
    {:ok, response}
  end

  @impl true
  def ocr_vision(_image_data, _opts) do
    {:ok, "Mock vision OCR text with amounts and dates."}
  end
end
