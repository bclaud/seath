defmodule Seath.OCR.Ollama do
  @moduledoc """
  Ollama OCR provider.

  Uses a multimodal Ollama model (default: llava) to extract text
  from document images. Requires a running Ollama instance.
  Configure via `OLLAMA_BASE_URL` and `OLLAMA_OCR_MODEL` environment
  variables or equivalent config entries.
  """
  @behaviour Seath.OCR.Provider

  @impl true
  def extract(file_path) do
    config = Application.get_env(:seath, __MODULE__, [])
    base_url = Keyword.get(config, :base_url) || System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")
    model = Keyword.get(config, :model) || System.get_env("OLLAMA_OCR_MODEL", "llava")

    do_extract(file_path, base_url, model)
  end

  defp do_extract(file_path, base_url, model) do
    with {:ok, file_data} <- File.read(file_path) do
      image_data = Base.encode64(file_data)

      body = %{
        model: model,
        stream: false,
        messages: [
          %{
            role: "user",
            content: "Extract all text from this document image. Return only the extracted text, nothing else.",
            images: [image_data]
          }
        ]
      }

      case Req.post("#{base_url}/api/chat", json: body) do
        {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
          {:ok, String.trim(content)}

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_response, status, body}}

        {:error, %Mint.TransportError{reason: :econnrefused}} ->
          {:error, :connection_refused}

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
