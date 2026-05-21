# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :seath,
  ecto_repos: [Seath.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :seath, :storage, upload_dir: "priv/uploads"

# Configure the endpoint
config :seath, SeathWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SeathWeb.ErrorHTML, json: SeathWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Seath.PubSub,
  live_view: [signing_salt: "0D2AN4Yg"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :seath, Seath.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  seath: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  seath: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure Oban
config :seath, Oban,
  repo: Seath.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 3 * * *", Seath.Workers.ApplyArchiveRules, queue: :archive_cron},
       {"*/5 * * * *", Seath.Workers.WatchedFolderWorker, queue: :ingest}
     ]}
  ],
  queues: [ingest: 5, ocr: 3, classify: 3, archive: 2, archive_cron: 1]

# Configure watched folder auto-import
config :seath, :watched_folder,
  path: "priv/watched",
  processed_subdir: "processed",
  allowed_extensions: ~w(.pdf .png .jpg .jpeg .tiff .txt)

# Configure OCR provider — set via env var or runtime config
# Available: Seath.OCR.Azure, Seath.OCR.Ollama

# Configure LLM provider — set via env var or runtime config
# Available: Seath.LLM.Ollama

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
