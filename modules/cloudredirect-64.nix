# 64-bit cloud_redirect.so built from the moon-fork source tree.
#
# The .so committed at the repo root is a 32-bit build: it targets the
# downgraded client that Valve retired in November 2026. The current 64-bit
# client needs a hook of its own ELF class, and the repo's Linux default
# build is native 64-bit (LINUX_32BIT=ON is the opt-in for 32-bit), with only
# dl and pthread to link. Both module sides (NixOS LD_PRELOAD and the
# home-manager link) build this with their own pkgs -- the same nixpkgs via
# follows, so both land on one identical store path.
#
# Hooking is architecture-agnostic: an RTTI type-string scan for
# CClientUnifiedServiceTransport (Itanium mangling is class-only), maps
# walking and vtable patching -- no pointer-size assumptions.
{
  pkgs,
  src,
}: let
  # Libraries the hook must resolve against the same way the audit objects
  # do: libstdc++/libgcc from the same nixpkgs as Steam's FHS, while libc
  # keeps coming from the already-loaded process copy (single-libc rule).
  # glibc deliberately absent from the RUNPATH.
  hookRpath = pkgs.stdenv.cc.cc.lib;
in
  pkgs.stdenv.mkDerivation {
    name = "cloudredirect-64";
    inherit src;

    nativeBuildInputs = [pkgs.cmake pkgs.patchelf];

    cmakeFlags = ["-DCMAKE_BUILD_TYPE=Release"];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp cloud_redirect.so "$out/"
      # Replace the build RUNPATH (which fixup narrows to glibc + gcc-lib)
      # with the explicit single-libc path from hookRpath.
      patchelf --set-rpath "${hookRpath}/lib" "$out/cloud_redirect.so"
      runHook postInstall
    '';

    # No separate dev outputs or meta needed; consumed only as a .so path.
  }
