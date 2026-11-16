{
  sls-steam,
  slsteam-moon,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.nix-crab;

  upstream = sls-steam.packages.${pkgs.stdenv.hostPlatform.system}.sls-steam;

  # slsteam-moon is a fork of SLSsteam that produces the same two artefacts
  # (SLSsteam.so + library-inject.so) plus a native Lua manifest importer. It
  # ships no flake, so it is built from source with the same 32-bit toolchain
  # upstream uses in its own nix-modules/default.nix.
  slsteamMoon = pkgs.pkgsi686Linux.stdenv.mkDerivation {
    pname = "slsteam-moon";
    version = "0.0.0";
    src = slsteam-moon;
    # utils.hpp uses fixed-width integers before utils.cpp includes cstdint.
    # GCC 15 no longer supplies those declarations through other headers.
    postPatch = ''
      substituteInPlace src/utils.hpp \
        --replace-fail '#pragma once' '#pragma once
      #include <cstdint>'
    '';
    nativeBuildInputs = with pkgs; [pkg-config];
    buildInputs = with pkgs.pkgsi686Linux; [openssl curl];
    # pattern-refresh is a native host helper we don't need; only the two
    # Steam-loaded i386 objects are injected.
    buildPhase = ''
      runHook preBuild
      make -j"$NIX_BUILD_CORES" bin/SLSsteam.so bin/library-inject.so
      runHook postBuild
    '';
    # -O3 -flto over ~100 translation units; the Makefile only marks `clean`
    # and `rebuild` as .NOTPARALLEL, so the object targets take -j fine.
    enableParallelBuilding = true;
    installPhase = ''
      mkdir -p "$out"
      cp bin/SLSsteam.so "$out/"
      cp bin/library-inject.so "$out/"
    '';
    meta = {
      description = "SLSsteam fork with a Lua manifest importer (slsteam-moon)";
      homepage = "https://github.com/swwayps/slsteam-moon";
      license = lib.licenses.agpl3Only;
      platforms = lib.platforms.linux;
    };
  };

  # Both forks ship the same two artefacts under the same names, so the choice
  # is one store path, not two branches of wiring.
  slsRaw =
    if cfg.slssteam-moon.enable
    then slsteamMoon
    else upstream;

  # Both forks ship their audit objects under one store path, so the choice
  # is one derivation, not two branches of wiring. The artefact lists differ:
  # upstream merged library-inject.so into SLSsteam.so (single audit object,
  # current setup.sh), the moon fork still builds and needs the pair.
  slsArtefacts =
    if cfg.slssteam-moon.enable
    then ["library-inject.so" "SLSsteam.so"]
    else ["SLSsteam.so"];

  # The audit objects carry a RUNPATH onto a glibc that is not the one Steam's
  # FHS env loads (upstream's prebuilts onto their own glibc/libstdc++, the
  # moon build onto the 32-bit toolchain's). Steam's FHS already has a 32-bit
  # libc loaded, and the loader honours that RUNPATH: a second libc.so.6 ends
  # up in the same 32-bit process. The canary is then written by one libc and
  # verified by the other, so every 32-bit program dies with "*** stack
  # smashing detected ***". Upstream's own nix build now strips the RUNPATH
  # too (postFixup); doing it here keeps the moon build in the same shape.
  # The store name mirrors the fork so nix-crab-status can read the injected
  # fork out of the live LD_AUDIT path.
  sls = pkgs.runCommand (lib.optionalString cfg.slssteam-moon.enable "slsteam-moon-audit"
    + lib.optionalString (!cfg.slssteam-moon.enable) "sls-steam-audit") {
    nativeBuildInputs = [pkgs.patchelf];
  } ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (f: ''
      cp ${slsRaw}/${f} "$out/${f}"
      chmod u+w "$out/${f}"
      patchelf --remove-rpath "$out/${f}"
    '') slsArtefacts}
  '';
in {
  options.programs.nix-crab = {
    slssteam.enable = lib.mkEnableOption "SLSsteam (upstream) injection into Steam";

    slssteam.extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables injected into Steam";
    };

    slssteam-moon.enable = lib.mkEnableOption ''
      slsteam-moon (SLSsteam fork with a Lua manifest importer) instead of
      upstream SLSsteam. Takes precedence over slssteam.enable; required by
      the home module's luatools option.
    '';
  };

  config = lib.mkIf (cfg.slssteam.enable || cfg.slssteam-moon.enable) {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        extraEnv =
          {
            LD_AUDIT =
              lib.concatStringsSep ":" (map (f: "${sls}/${f}") slsArtefacts);
          }
          // cfg.slssteam.extraEnv;
        # The FHS wrapper never binds /sys: bubblewrap starts with a fresh
        # mount namespace where /sys does not exist, and the auto-mount loop
        # cannot bind a mountpoint onto itself. Mesa then cannot resolve
        # /sys/dev/char/226:* or /sys/class/drm, reports "failed to retrieve
        # device information", refuses to load i915/iris and falls back to
        # llvmpipe. Steam's 32-bit vgui2 gets no GLX visual and fatal-asserts
        # with "glXChooseVisual failed". A read-only bind is all it needs.
        #
        extraBwrapArgs = ["--ro-bind /sys /sys"];
      };
    };
  };
}
