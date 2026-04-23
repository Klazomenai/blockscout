{ pkgs, ... }:

let
  # Match the BEAM pairing used by flake.nix — OTP 27 + Elixir 1.19.
  # Blockscout requires `elixir ~> 1.19` (see mix.exs); the default elixir
  # package in nixpkgs is paired with a lower OTP, so we pull the pairing
  # explicitly from the erlang_27 scope.
  beam27 = pkgs.beam.packages.erlang_27;
  elixir = beam27.elixir_1_19;
in
{
  languages.elixir = {
    enable = true;
    package = elixir;
  };

  packages = with pkgs; [
    # Native extension toolchain (ezstd, bcrypt_elixir, etc.)
    gcc
    gnumake
    pkg-config
    zstd # used by :ezstd at build/link time

    # Node for the webpack watcher in apps/block_scout_web/config/dev.exs.
    # Major version matches the pin in `.tool-versions` (nodejs 20.17.0);
    # without this, `mix phx.server` fails to launch the asset watcher.
    nodejs_20

    # VCS
    git
    git-lfs

    # Nix hygiene
    nixfmt-rfc-style
    statix
    deadnix
  ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    linuxHeaders
  ];

  git-hooks.hooks = {
    # Nix hygiene
    nixfmt-rfc-style.enable = true;
    statix.enable = true;
    deadnix.enable = true;

    # Elixir formatting — non-blocking verification that tracked Elixir
    # files are formatted. Uses `.formatter.exs` at the project root.
    mix-format = {
      enable = true;
      name = "mix format --check-formatted";
      entry = "mix format --check-formatted";
      files = "\\.(ex|exs)$";
      pass_filenames = false;
    };
  };

  enterShell = ''
    echo "Blockscout development environment"
    echo ""
    echo "Nix entrypoints (canonical hermetic build):"
    echo "  nix build .#default    Build the Blockscout release"
    echo "  nix flake check        Run hermetic flake checks"
    echo ""
    echo "Mix wrappers (idiomatic Elixir task-runner form):"
    echo "  mix nix.build          Alias for \`nix build .#default\`"
    echo "  mix nix.check          Alias for \`nix flake check\`"
    echo ""
    echo "Pinned versions:"
    elixir --version | sed 's/^/  /'
  '';
}
