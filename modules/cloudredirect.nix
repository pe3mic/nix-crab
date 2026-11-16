{
  cloudredirect,
  cloudredirect-moon,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  # The prebuilt .so at the moon-fork repo root is 32-bit (downgraded-client
  # era); the current 64-bit client gets a hook built from the same source.
  cloudredirect64 = import ./cloudredirect-64.nix {
    inherit pkgs;
    src = cloudredirect-moon;
  };
in {
  options.programs.nix-crab.cloudredirect = {
    enable = lib.mkEnableOption "Enable CloudRedirect";

    moon.enable = lib.mkEnableOption ''
      the 32-bit prebuilt cloudredirect-moon hook instead of the source-built
      64-bit one. The moon fork scans <Steam>/config/stplug-in/*.lua and
      luaappids.yaml, so it recognises games added by the LuaTools stack.
      Only enable for LuaTools on the downgraded 32-bit client; the 64-bit
      build is the default.
    '';
  };

  config = lib.mkIf config.programs.nix-crab.cloudredirect.enable {
    programs.nix-crab.slssteam.extraEnv.LD_PRELOAD =
      if config.programs.nix-crab.cloudredirect.moon.enable
      then "${cloudredirect}"
      else "${cloudredirect64}/cloud_redirect.so";
  };
}
