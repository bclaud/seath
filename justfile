set dotenv-load := true

default:
    @just --list

# === Server ===

serve:
    mix phx.server

serve-iex:
    iex -S mix phx.server

server-deps:
    mix deps.get

server-db-setup: server-db-start server-db-create server-db-migrate

server-db-create:
    mix ecto.create

server-db-migrate:
    mix ecto.migrate

server-db-reset:
    mix ecto.reset

server-db-start:
    @pg_isready -q || pg_ctl -D /tmp/seath-postgres -l /tmp/seath-postgres.log start

server-db-stop:
    pg_ctl -D /tmp/seath-postgres stop 2>/dev/null || true

server-setup: server-deps server-db-setup

server-test:
    mix test

server-lint:
    mix credo --strict

# === Assets ===

assets-deps:
    npm install --prefix assets

assets-build:
    npm run deploy --prefix assets

assets-watch:
    npm run watch --prefix assets

# === Setup ===

setup: server-setup assets-deps assets-build

# === Cleanup ===

clean: server-db-stop
    rm -rf /tmp/seath-postgres _build deps assets/node_modules
