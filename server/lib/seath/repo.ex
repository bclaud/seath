defmodule Seath.Repo do
  use Ecto.Repo,
    otp_app: :seath,
    adapter: Ecto.Adapters.Postgres
end
