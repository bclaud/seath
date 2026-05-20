defmodule Seath.OCR.Azure do
  @moduledoc """
  Azure Document Intelligence OCR provider.

  Uses Azure's prebuilt-read model to extract text from documents.
  Requires `AZURE_DI_ENDPOINT` and `AZURE_DI_KEY` environment variables
  or equivalent config entries.
  """
  @behaviour Seath.OCR.Provider

  @impl true
  def extract(file_path) do
    config = Application.get_env(:seath, __MODULE__, [])
    endpoint = Keyword.get(config, :endpoint) || System.get_env("AZURE_DI_ENDPOINT")
    key = Keyword.get(config, :key) || System.get_env("AZURE_DI_KEY")

    if is_nil(endpoint) or is_nil(key) do
      {:error, :not_configured}
    else
      do_extract(file_path, endpoint, key)
    end
  end

  defp do_extract(file_path, endpoint, key) do
    url = "#{endpoint}/formrecognizer/documentModels/prebuilt-read:analyze?api-version=2023-07-31"
    body = File.read!(file_path)

    case Req.post(url,
           headers: %{
             "content-type" => "application/octet-stream",
             "ocp-apim-subscription-key" => key
           },
           body: body
         ) do
      {:ok, %{status: 202, headers: headers}} ->
        operation_location = List.keyfind(headers, "operation-location", 0)

        if operation_location do
          poll_result(elem(operation_location, 1), key)
        else
          {:error, :no_operation_location}
        end

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp poll_result(url, key, attempts \\ 0) do
    if attempts > 30 do
      {:error, :timeout}
    else
      Process.sleep(1000)

      case Req.get(url, headers: %{"ocp-apim-subscription-key" => key}) do
        {:ok, %{status: 200, body: body}} ->
          text = extract_text_from_result(body)
          {:ok, text}

        {:ok, %{status: 202}} ->
          poll_result(url, key, attempts + 1)

        {:ok, %{status: status}} ->
          {:error, {:unexpected_status, status}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp extract_text_from_result(%{"analyzeResult" => %{"content" => content}}), do: content
  defp extract_text_from_result(_), do: ""
end
