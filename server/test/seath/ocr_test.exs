defmodule Seath.OCRTest do
  use Seath.DataCase

  alias Seath.OCR

  describe "impl/0" do
    test "returns the configured OCR provider" do
      assert OCR.impl() == Seath.OCR.Mock
    end
  end

  describe "extract/1" do
    test "delegates to the configured provider" do
      assert {:ok, "Mock extracted text from document."} = OCR.extract("/some/file.pdf")
    end
  end
end
