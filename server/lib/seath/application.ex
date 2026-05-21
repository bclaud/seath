defmodule Seath.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SeathWeb.Telemetry,
      Seath.Repo,
      {DNSCluster, query: Application.get_env(:seath, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Seath.PubSub},
      {Oban, Application.fetch_env!(:seath, Oban)},
      SeathWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Seath.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      # Load persisted settings from database after app starts
      load_settings()
      {:ok, pid}
    end
  end

  defp load_settings do
    try do
      Seath.Settings.load_and_apply()
    rescue
      _ -> :ok
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SeathWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
