{
  description = "Blockscout - blockchain explorer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Use OTP 27 beam packages (Blockscout requires OTP 27.3.x)
        beam27 = pkgs.beam.packages.erlang_27;

        # Static zstd library for the ezstd NIF.
        # ezstd's build_deps.sh tries to git clone facebook/zstd — blocked
        # in the Nix sandbox. We build just libzstd.a from source.
        zstdStatic = pkgs.stdenv.mkDerivation {
          pname = "zstd-static";
          version = pkgs.zstd.version;
          src = pkgs.zstd.src;
          nativeBuildInputs = [ pkgs.gnumake ];
          buildPhase = ''
            export CFLAGS="-O2 -fPIC"
            make -C lib lib-release -j $NIX_BUILD_CORES
          '';
          installPhase = ''
            mkdir -p $out/lib $out/include
            cp lib/libzstd.a $out/lib/
            cp lib/zstd.h lib/zstd_errors.h lib/zdict.h $out/include/
          '';
        };

        # Pre-downloaded Rustler precompiled NIF tarballs.
        # rustler_precompiled tries to download these at compile time, which
        # fails in the Nix sandbox. We pre-fetch them here (FODs have network)
        # and point RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH at the result — the
        # library then reuses cached artifacts without any download attempt.
        #
        # Filename pattern: lib{crate}-v{version}-nif-{nif}-{target}.so.tar.gz
        # Six packages advertise ["2.15", "2.16"] — picks 2.16.
        # ex_eth_bls advertises ["2.16", "2.17"] — picks 2.17 on OTP 27.
        # Target: x86_64-unknown-linux-gnu (standard glibc)

        # Helper: fetch a single precompiled NIF tarball
        fetchNif =
          {
            name,
            url,
            hash,
          }:
          pkgs.fetchurl {
            inherit name url hash;
          };

        # Collection of all 7 Rustler precompiled NIF tarballs for x86_64-linux-gnu, NIF 2.16
        nifTarballs = [
          {
            name = "libcafezinho-v0.4.4-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/ayrat555/cafezinho/releases/download/v0.4.4/libcafezinho-v0.4.4-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-oRZW1DEt3iRuoa6B3QiLm1b9KiBvSyJng0B5vv4xzv8=";
          }
          {
            name = "libevil_crc32c-v0.2.9-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/ayrat555/evil_crc32c/releases/download/v0.2.9/libevil_crc32c-v0.2.9-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-shKgLfoD/NbT42j7/A65nAsQ31HKjbsh6/ioBEmhDN0=";
          }
          # ex_brotli uses default nif_versions ["2.15"] — no override
          {
            name = "libex_brotli-v0.5.0-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/mfeckie/ex_brotli/releases/download/0.5.0/libex_brotli-v0.5.0-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-TuIr14IIY2Ty37poxY8h84GtmclSW0YSPcXf0rGCEqI=";
          }
          {
            name = "libex_eth_bls-v0.1.0-nif-2.17-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/blockscout/ex_eth_bls/releases/download/v0.1.0/libex_eth_bls-v0.1.0-nif-2.17-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-gCGKv8IlrlKgTI6NY72t8DAqIj12z5FZ7gpmchplfJo=";
          }
          {
            name = "libexkeccak-v0.7.8-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/exWeb3/ex_keccak/releases/download/v0.7.8/libexkeccak-v0.7.8-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-1Ej5BhCzs0Kw8i3EQm5/0+6aXD4ZrRxWbEOB5Fm+NWY=";
          }
          {
            name = "libex_pbkdf2-v0.8.5-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/ayrat555/ex_pbkdf2/releases/download/v0.8.5/libex_pbkdf2-v0.8.5-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-54peWmCajQw2+oodrA1fYijuJcnRGVg0vKqDPteSrrU=";
          }
          {
            name = "libex_secp256k1-v0.8.0-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/ayrat555/ex_secp256k1/releases/download/v0.8.0/libex_secp256k1-v0.8.0-nif-2.16-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-Tp1ySChaaMkeuLiUeXek4A8zlBkIzDKaoEfP6HcmVS4=";
          }
          # siwe (Sign-In-With-Ethereum) is a git dep, also has a Rustler NIF
          {
            name = "libsiwe_native-v0.6.0-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz";
            url = "https://github.com/royal-markets/siwe-ex/releases/download/v0.6.0/libsiwe_native-v0.6.0-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz";
            hash = "sha256-nrRKyulG9yImbSNdEQEDR3d18vcpu6xK5uzZ4HCyWko=";
          }
        ];

        # Assemble all NIF tarballs into a single cache directory.
        rustlerNifCache = pkgs.runCommand "rustler-nif-cache" { } ''
          mkdir -p $out
          ${pkgs.lib.concatMapStringsSep "\n" (
            t: "cp ${fetchNif t} $out/${t.name}"
          ) nifTarballs}
        '';

        # Blockscout requires Elixir ~> 1.19; the default beam27.elixir is 1.18.
        elixir = beam27.elixir_1_19;

        blockscout = beam27.mixRelease {
          pname = "blockscout";
          version = "11.0.0";
          src = ./.;

          inherit elixir;

          mixReleaseName = "blockscout";

          mixFodDeps = beam27.fetchMixDeps {
            pname = "mix-deps-blockscout";
            src = ./.;
            version = "11.0.0";
            hash = "sha256-hi8Kq8j91LKQDD8GroLESPnzBfwUeJsszb1lTa0k2iI=";
            inherit elixir;
          };

          env = {
            # Point rustler_precompiled at our pre-populated cache directory.
            # The library explicitly supports this for Nix/sandboxed builds —
            # it reuses cached tarballs without attempting any download.
            # See: rustler_precompiled/lib/rustler_precompiled.ex -> cache_dir/1
            RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH = "${rustlerNifCache}";
          };

          nativeBuildInputs = with pkgs; [
            # C toolchain for native extensions (ezstd, bcrypt_elixir, etc.)
            gcc
            gnumake
            cmake
            pkg-config

            # System libraries
            gmp.dev
            automake
            libtool
            python3
          ];

          buildInputs = with pkgs; [
            # Runtime libraries for NIF shared objects
            gmp
            openssl
          ];

          # Fix dependency build scripts BEFORE mix deps.compile runs.
          preConfigure = ''
            # Fix shebangs and permissions in dependency scripts.
            # 1. cp --no-preserve=mode strips execute bits from scripts
            # 2. The Nix sandbox lacks /usr/bin/env so shebangs need patching
            find "$MIX_DEPS_PATH" -name "*.sh" -exec chmod +x {} +
            patchShebangs "$MIX_DEPS_PATH"

            # ezstd's build_deps.sh tries to git clone facebook/zstd from
            # GitHub — blocked in the Nix sandbox. Skip it entirely by
            # providing the pre-built libzstd.a and headers from nixpkgs.
            mkdir -p "$MIX_DEPS_PATH/ezstd/_build/deps/zstd/lib"
            cp ${zstdStatic}/lib/libzstd.a "$MIX_DEPS_PATH/ezstd/_build/deps/zstd/lib/"
            cp ${zstdStatic}/include/*.h "$MIX_DEPS_PATH/ezstd/_build/deps/zstd/lib/"

            # Remove nft_media_handler from umbrella apps. Mix compiles all
            # umbrella apps regardless of release config, and nft_media_handler
            # depends on evision (OpenCV) which is heavy and not needed for MVP.
            rm -rf apps/nft_media_handler
          '';

          doCheck = false;

          # The Dockerfile copies config_helper.exs into the release at two
          # locations. mix.exs's copy_prod_runtime_config only copies runtime.exs.
          # Replicate the Dockerfile's missing copy so runtime.exs can find it.
          postInstall = ''
            mkdir -p "$out/config" "$out/releases/11.0.0"
            cp config/config_helper.exs "$out/config/config_helper.exs"
            cp config/config_helper.exs "$out/releases/11.0.0/config_helper.exs"
            # Copy precompiles assets if they exist (referenced from config)
            if [ -d config/assets ]; then
              mkdir -p "$out/config/assets"
              cp -r config/assets/. "$out/config/assets/" || true
            fi
          '';

          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            # Provide a cookie — mixRelease strips releases/COOKIE by default
            export RELEASE_COOKIE="nix-install-check"
            # Verify the BEAM release boots and all NIFs load
            echo "=== Running blockscout eval ==="
            $out/bin/blockscout eval 'IO.puts("BEAM_RELEASE_OK")'
            echo "=== Checking nft_media_handler is excluded ==="
            ! ls -d $out/lib/nft_media_handler-* 2>/dev/null
            echo "=== Install check passed ==="
            runHook postInstallCheck
          '';

          meta = with pkgs.lib; {
            description = "Blockchain explorer for EVM chains";
            homepage = "https://github.com/blockscout/blockscout";
            license = licenses.gpl3Plus;
            mainProgram = "blockscout";
            platforms = platforms.linux;
          };
        };
      in
      {
        packages.default = blockscout;

        checks.${system}.default = blockscout;
      }
    );
}
