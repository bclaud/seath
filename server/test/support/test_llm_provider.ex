defmodule Seath.TestLLMProvider do
  @moduledoc """
  Test LLM provider that returns a classification with specific tags and document type.
  """
  @behaviour Seath.LLM.Provider

  @impl true
  def classify(_text, _available_tags, _available_types, _opts \\ []) do
    {:ok,
     %{
       title: "Test Invoice",
       document_type: "invoice",
       tags: ["invoice", "finance"],
       correspondent: "Acme Corp",
       involved_parties: [%{name: "Acme Corp", role: "sender"}]
     }}
  end

  @impl true
  def think(_text, _opts \\ []) do
    {:ok,
     %{
       reasoning: "This document is an invoice from Acme Corp. It contains financial details including amounts and dates.",
       extracted_entities: ["Acme Corp", "João Silva"],
       extracted_amounts: ["R$ 1.500,00"],
       extracted_dates: ["2024-03-15"],
       summary: "Invoice for consulting services from Acme Corp"
     }}
  end

  @impl true
  def classify_from_reasoning(_thinking, _text, _available_tags, _available_types, _opts \\ []) do
    {:ok,
     %{
       title: "Test Invoice",
       document_type: "invoice",
       tags: ["invoice", "finance"],
       correspondent: "Acme Corp",
       involved_parties: [%{name: "Acme Corp", role: "sender"}, %{name: "João Silva", role: "recipient"}]
     }}
  end

  @impl true
  def verify(classification, text) do
    text_lower = String.downcase(text)
    flagged = []
    verified = []

    {verified, flagged} =
      if correspondent = Map.get(classification, :correspondent) do
        if String.contains?(text_lower, String.downcase(correspondent)) do
          {verified ++ ["correspondent"], flagged}
        else
          {verified, flagged ++ [%{field: "correspondent", reason: "Not found in text"}]}
        end
      else
        {verified, flagged}
      end

    passed? = flagged == []
    {:ok, %{passed: passed?, verified_fields: verified, flagged_fields: flagged}}
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

  @impl true
  def chat_with_tools(_messages, _tools, _opts) do
    {:ok, %{content: "This is a mock tool-calling response.", tool_calls: []}}
  end
end
