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
    # Restricted to x86_64-linux: the Rustler precompiled NIF tarballs in
    # nifTarballs are hardcoded for x86_64-unknown-linux-gnu. Other systems
    # would need their own per-target NIF cache (or local Rust compilation,
    # which currently fails because Cargo can't reach crates.io in the sandbox).
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
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

        # All 8 Rustler precompiled NIF tarballs for x86_64-unknown-linux-gnu.
        # Per-package NIF version varies based on each package's nif_versions
        # list and the runtime's max NIF version (OTP 27 supports up to 2.17).
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
          ${pkgs.lib.concatMapStringsSep "\n" (t: "cp ${fetchNif t} $out/${t.name}") nifTarballs}
        '';

        # Blockscout requires Elixir ~> 1.19; the default beam27.elixir is 1.18.
        elixir = beam27.elixir_1_19;

        blockscoutVersion = "11.0.0";

        blockscout = beam27.mixRelease {
          pname = "blockscout";
          version = blockscoutVersion;
          src = ./.;

          inherit elixir;

          mixReleaseName = "blockscout";

          # Mix dependency closure as a fixed-output derivation. The
          # output bytes here can drift on identical declared inputs
          # (mix.lock + mix.exs) because Mix's resolver consults the
          # live hex registry when deciding whether to fetch optional
          # transitive deps that are NOT pinned in mix.lock. If the
          # registry's package metadata changes (new optional-dep
          # version published, etc.), Mix can flip its decision about
          # whether to include that dep — which changes the output
          # tree and therefore the recorded hash.
          #
          # Concrete observed instance (issue #7):
          #   - rustler is declared `optional: true` by 10 packages
          #     (cafezinho, evil_crc32c, ex_brotli, ex_eth_bls,
          #     ex_keccak, ex_pbkdf2, ex_secp256k1, image,
          #     rustler_precompiled, siwe). None pin it.
          #   - On 2026-04-15, Mix decided to fetch rustler 0.37.3.
          #   - On 2026-04-27, Mix decided to skip it.
          #   - Same mix.lock, same mix.exs, same nixpkgs-pinned mix
          #     binary, different output bytes.
          #
          # Maintenance recipe when the FOD hash drifts again:
          #
          #   1. Reproduce locally with the SAME Mix/Elixir/OTP toolchain
          #      this flake itself uses (sourced from `flake.lock`'s
          #      pinned nixpkgs rev, NOT from the user's flake registry
          #      — the registry's `nixpkgs` typically tracks unstable
          #      and can drift far ahead of our pinned rev, producing
          #      different `mix deps.get` output and defeating the
          #      reproduction):
          #        nix shell --inputs-from . nixpkgs#beam27Packages.elixir_1_19 nixpkgs#git
          #        export HEX_HOME=$(mktemp -d) MIX_HOME=$(mktemp -d)
          #        mix local.hex --force --if-missing
          #        mix local.rebar --force --if-missing
          #        mix deps.get
          #        git diff mix.lock
          #
          #   2. If `mix deps.get` adds entries to mix.lock, commit
          #      the lockfile delta as a `chore(deps)` commit FIRST
          #      (this converts registry-state-sensitive resolution
          #      into lockfile-pinned resolution at root).
          #
          #   3. Set the hash here to `pkgs.lib.fakeHash`, then run
          #      `nix build .#default 2>&1 | grep got:` to capture
          #      the actual output hash. Replace fakeHash with that
          #      value, commit as `fix(nix): rotate mixFodDeps hash`.
          #
          #   4. Run a clean `nix build .#default` to verify
          #      end-to-end build succeeds against the new hash.
          mixFodDeps = beam27.fetchMixDeps {
            pname = "mix-deps-blockscout";
            src = ./.;
            version = blockscoutVersion;
            hash = "sha256-i11gJiWjgoCcKRIt0ePjMQOqXTJIVEETQv4s75pEpNU=";
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

          # Local symptom suppression: prevent the
          # `Explorer.Migrator.ReindexDuplicatedInternalTransactions`
          # GenServer from being started by the application
          # supervisor.
          #
          # What we observe in this fork's build of v11:
          #
          # - At BEAM startup the supervisor starts the migrator
          #   (verified by reading `apps/explorer/lib/explorer/
          #   application.ex:201` — the `configure_mode_dependent_
          #   process(Explorer.Migrator.ReindexDuplicatedInternalTransactions,
          #   :indexer),` line we substitute below).
          # - The migrator's `unprocessed_data_query/1`
          #   (verified at `apps/explorer/lib/explorer/migrator/
          #   reindex_duplicated_internal_transactions.ex:65-71`)
          #   does
          #   `from(it in InternalTransaction,
          #     select: it.block_hash,
          #     where: not is_nil(it.block_hash),
          #     group_by: [it.block_hash, it.transaction_index, it.index], …)`.
          # - The `Explorer.Chain.InternalTransaction` schema
          #   (verified at `apps/explorer/lib/explorer/chain/
          #   internal_transaction.ex:56-76`) declares no
          #   `:block_hash` field.
          # - On every `:migrate_batch` tick the GenServer raises
          #   `(Ecto.QueryError) field `block_hash` in `select`
          #   does not exist in schema Explorer.Chain.
          #   InternalTransaction`. The supervisor restarts it and
          #   the cycle repeats; the journal shows the
          #   error stacktrace clustered at sub-second cadence.
          #   Observed in integration-VM runs of
          #   klazomenai/autonity-blockscout-nixos.
          #
          # We do NOT know:
          # - Whether the schema/migrator combination is
          #   intentional, transitional, or unintended from
          #   upstream's perspective.
          # - Whether upstream is aware, planning a fix, or has a
          #   different code path in mind.
          #
          # What this patch does: deletes the supervisor child-spec
          # line so the migrator GenServer never starts. Rationale:
          # without an independent verification of upstream intent,
          # we are not changing the migrator's source — only
          # preventing its execution in our build. The migrator's
          # source file remains in-tree, the schema remains
          # in-tree, no other code is touched.
          #
          # In-tree references to the unstarted module:
          # `apps/explorer/lib/explorer/chain/import/runner/
          # heavy_db_index_operation/create_internal_transactions_block_number_transaction_index_index_unique_index.ex`
          # calls `MigrationStatus.fetch(migration_name())`
          # against this migrator. With the GenServer never
          # starting, that lookup returns `nil` and the dependent
          # index-op's wait branch fires — same shape as a fresh
          # database where the migration has not yet completed.
          #
          # Drop this prePatch when:
          # - independent verification confirms an upstream fix
          #   (or, equivalently, this fork rebases past a tree
          #   where the schema-vs-query divergence is gone), OR
          # - we have direct guidance from upstream that the
          #   migrator should run as-is on our schema and this
          #   patch is wrong.
          # The matching `extraPostMigrate` fixture in
          # `klazomenai/autonity-blockscout-nixos`'s integration
          # test can be removed at the same time.
          prePatch = ''
            substituteInPlace apps/explorer/lib/explorer/application.ex \
              --replace-fail \
                "configure_mode_dependent_process(Explorer.Migrator.ReindexDuplicatedInternalTransactions, :indexer)," \
                ""
          '';

          # Patch mix.exs to remove nft_media_handler from the release. This
          # is done at Nix build time only — the committed mix.exs is left
          # unchanged so that other build paths (Docker, NFT_MEDIA_HANDLER_IS_WORKER
          # mode, docker-compose nft_media_handler service) continue to work.
          # We also remove the umbrella app directory because Mix compiles all
          # umbrella apps regardless of release config, and nft_media_handler
          # depends on evision (OpenCV) which is out of MVP scope.
          postPatch = ''
            substituteInPlace mix.exs \
              --replace-fail "            nft_media_handler: :permanent" "" \
              --replace-fail "            utils: :permanent," "            utils: :permanent"
            rm -rf apps/nft_media_handler
          '';

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
          '';

          doCheck = false;

          # The Dockerfile copies config_helper.exs into the release at two
          # locations. mix.exs's copy_prod_runtime_config only copies runtime.exs.
          # Replicate the Dockerfile's missing copy so runtime.exs can find it.
          postInstall = ''
            mkdir -p "$out/config" "$out/releases/${blockscoutVersion}"
            cp config/config_helper.exs "$out/config/config_helper.exs"
            cp config/config_helper.exs "$out/releases/${blockscoutVersion}/config_helper.exs"
            # Copy precompiled assets if they exist (referenced from config)
            if [ -d config/assets ]; then
              mkdir -p "$out/config/assets"
              cp -r config/assets/. "$out/config/assets/"
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
            license = licenses.gpl3Only;
            mainProgram = "blockscout";
            platforms = platforms.linux;
          };
        };
      in
      {
        packages.default = blockscout;
        packages.blockscout = blockscout;

        checks.default = blockscout;
      }
    );
}
