{
  description = "Flake for h3adcr-b on NixOS";

  nixConfig = {
    extra-substituters = ["https://at3mic.cachix.org"];
    extra-trusted-public-keys = [
      "at3mic.cachix.org-1:nrHEb10UDTgmmmvqaPdYt0RkF0mgcyCksUXaX7fIEHY="
    ];
  };

  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    accela = {
      type = "file";
      # Enter The Wired's bundle, which ships the AppImage. Versionless URL, so
      # unlike steamidra it needs no tag-list indirection and no pinned hash.
      url = "https://github.com/ciscosweater/enter-the-wired/releases/download/latest/deps.tar.gz";
      flake = false;
    };
    cloudredirect-moon = {
      url = "github:swwayps/cloudredirect-moon";
      flake = false;
    };
    millennium = {
      url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sls-steam = {
      url = "github:AceSLS/SLSsteam";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # SLSsteam fork with a native Lua manifest importer (the maintained path
    # for the LuaTools workflow on Linux). No flake, so it is built from source
    # in modules/slssteam.nix instead of being imported as a package set.
    slsteam-moon = {
      url = "github:swwayps/slsteam-moon";
      flake = false;
    };
    # Lumen (static Lua backend) + the LuaTools plugin port, both from the
    # slsteam-moon maintainer. Pinned by git rev, not the versionless
    # releases/latest URLs (those change content on every release and break
    # the lock's narHash). Lumen's portable binary is committed at
    # dist/lumen-linux.zip; the plugin is built from its plugin/ source tree.
    lumen = {
      url = "github:swwayps/lumen";
      flake = false;
    };
    luatools-moon = {
      url = "github:swwayps/luatools-moon";
      flake = false;
    };
    steamnetsock = {
      type = "file";
      url = "https://github.com/yesyes0649/steamnetsock-patch/releases/latest/download/fix.so";
      flake = false;
    };
    steamidra = {
      type = "file";
      # Tag list, not releases/latest: that JSON embeds per-asset download
      # counters, so its narHash changes within the hour and every eval after
      # the tarball TTL dies with a narHash mismatch. /tags only changes when a
      # new tag is pushed. `nix flake update` follows the newest release.
      url = "https://api.github.com/repos/drappula/SFF/tags";
      flake = false;
    };
  };

  outputs = {
    accela,
    cloudredirect-moon,
    home-manager,
    millennium,
    nixpkgs,
    self,
    sls-steam,
    slsteam-moon,
    lumen,
    luatools-moon,
    steamidra,
    steamnetsock,
  }: let
    # Prebuilt 32-bit hook + CLI, committed at the moon-fork repo root.
    # Used only by the moon.enable path (downgraded 32-bit client / LuaTools);
    # the default hook is built 64-bit from the same source in
    # modules/cloudredirect-64.nix.
    cloudredirect = "${cloudredirect-moon}/cloud_redirect.so";
    cloudredirect-cli = "${cloudredirect-moon}/cloud_redirect_cli";
  in {
    checks.x86_64-linux = import ./checks.nix {
      inherit self nixpkgs home-manager;
    };

    nixosModules.default = {
      imports = [
        (import ./modules/millennium.nix {inherit millennium;})
        (import ./modules/cloudredirect.nix {inherit cloudredirect cloudredirect-moon;})
        (import ./modules/slssteam.nix {inherit sls-steam slsteam-moon;})
        ./modules/downgrade.nix
      ];
    };

    homeModules.default = {
      imports = [
        (import ./modules/home.nix {inherit sls-steam steamnetsock cloudredirect cloudredirect-moon cloudredirect-cli;})
        ./modules/millennium-addons.nix
        (import ./modules/luatools-moon.nix {inherit lumen luatools-moon;})
        (import ./modules/steamidra.nix {inherit steamidra;})
        (import ./modules/accela.nix {inherit accela;})
      ];
    };
  };
}
