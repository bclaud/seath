# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Seath.Repo.insert!(%Seath.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Seath.Repo
alias Seath.DocumentTypes.DocumentType

IO.puts("Seeding default document types...")

default_types = [
  %{name: "invoice", description: "Invoice or bill for goods/services"},
  %{name: "receipt", description: "Proof of purchase or payment receipt"},
  %{name: "contract", description: "Signed agreement or contract"},
  %{name: "email", description: "Email correspondence or thread"},
  %{name: "letter", description: "Formal letter or correspondence"},
  %{name: "statement", description: "Bank statement, account statement, or periodic report"},
  %{name: "report", description: "Report, analysis, or summary document"}
]

Enum.each(default_types, fn attrs ->
  case Repo.get_by(DocumentType, name: attrs.name) do
    nil ->
      %DocumentType{}
      |> DocumentType.changeset(attrs)
      |> Repo.insert!()

      IO.puts("  Created document type: #{attrs.name}")

    _ ->
      IO.puts("  Already exists: #{attrs.name}")
  end
end)

IO.puts("Done seeding!")
