{
  description = "Seath — intelligent document management system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        elixir = pkgs.beam.packages.erlang_27.elixir_1_18;

        appInputs = with pkgs; [
          elixir
          erlang_27
          nodejs_22
          postgresql_16
          inotify-tools
          just
        ];

        devInputs = with pkgs; [
          nixpkgs-fmt
          direnv
          gnumake
          gcc
        ];

        ollamaInputs = with pkgs; [
          ollama
        ];
      in
      {
        devShells.default = pkgs.mkShellNoCC {
          name = "seath-dev";
          shellHook =
            let
              erlangHook = ''
                export LANG=en_US.UTF-8
                export ERL_AFLAGS="-kernel shell_history enabled"

                if [ ! -d /tmp/seath-postgres ]; then
                  ${pkgs.postgresql_16}/bin/initdb -D /tmp/seath-postgres --locale=en_US.UTF-8
                  echo "unix_socket_directories = '/tmp'" >> /tmp/seath-postgres/postgresql.conf
                fi
                export PGDATA=/tmp/seath-postgres
                export PGHOST=localhost
                export PGDATABASE=seath_dev
                export PGPORT=5433
                export DATABASE_URL="postgresql://localhost:5433/seath_dev"
              '';
            in
            ''
              echo "🐚 seath dev shell"
              echo "  elixir:  ${elixir.version}"
              echo "  erlang:  ${pkgs.erlang_27.version}"
              echo "  node:    ${pkgs.nodejs_22.version}"
              echo "  postgres: ${pkgs.postgresql_16.version}"

              ${erlangHook}

              echo ""
              echo "  just              — task runner"
              echo "  nixpkgs-fmt       — nix formatter"
              echo ""
              echo "  just serve        — start phoenix server"
              echo "  just server-db-setup — create & migrate database"
              echo ""
              echo "  ollama            — local LLM/OCR (start separately)"
              echo "    Just run: ollama serve"
            '';

          buildInputs = appInputs ++ devInputs ++ ollamaInputs;
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    );
}
