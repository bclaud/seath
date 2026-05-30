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
  # Financial
  %{name: "invoice", description: "Invoice, nota fiscal, or bill for goods/services"},
  %{name: "receipt", description: "Proof of purchase, payment receipt, or comprovante"},
  %{name: "boleto", description: "Brazilian boleto bancário payment slip"},
  %{name: "bank_statement", description: "Bank or financial account statement / extrato bancário"},
  %{name: "credit_card_bill", description: "Credit card invoice or fatura de cartão"},
  %{name: "payslip", description: "Pay stub, holerite, or salary payment slip"},
  %{name: "tax_document", description: "Tax return, IRPF, or tax-related document"},
  %{name: "insurance", description: "Insurance policy, certificate, or claim document"},

  # Personal & ID
  %{name: "id_document", description: "RG, CPF, CNH, passport, or identity document"},
  %{name: "medical_record", description: "Medical report, health record, or laudo médico"},
  %{name: "prescription", description: "Medical prescription or receita médica"},
  %{name: "exam_result", description: "Lab test results, imaging, or diagnostic exam"},
  %{name: "certificate", description: "Course completion, birth, marriage, or civil certificate"},

  # Academic
  %{name: "academic_paper", description: "TCC, thesis, dissertation, or scientific article"},
  %{name: "homework", description: "School assignment, homework, or class activity"},
  %{name: "transcript", description: "Academic transcript or histórico escolar"},
  %{name: "diploma", description: "Degree diploma or graduation certificate"},
  %{name: "study_note", description: "Study notes, class notes, or summaries"},
  %{name: "presentation", description: "Slides, PowerPoint, or presentation material"},

  # Business & Work
  %{name: "memo", description: "Internal memo or interoffice communication / memorando"},
  %{name: "meeting_minutes", description: "Meeting notes or ata de reunião"},
  %{name: "proposal", description: "Business proposal, quote, budget, or orçamento"},
  %{name: "form", description: "Filled application, registration form, or formulário"},
  %{name: "manual", description: "User manual, guide, instruction, or handbook"},
  %{name: "spreadsheet", description: "Spreadsheet, planilha, or data table"},
  %{name: "report", description: "Analysis, report, or executive summary"},

  # Correspondence
  %{name: "letter", description: "Formal letter or written correspondence"},
  %{name: "email", description: "Email correspondence, thread, or printout"},

  # Legal
  %{name: "contract", description: "Signed agreement, contract, or legal termo"},
  %{name: "power_of_attorney", description: "Procuração, legal authorization, or mandate"}
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
