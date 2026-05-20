defmodule Seath.OCR.AzureTest do
  use Seath.DataCase

  alias Seath.OCR.Azure

  test "returns error when not configured" do
    assert {:error, :not_configured} = Azure.extract("nonexistent.pdf")
  end
end
