{
  lib,
  pkgs,
  self,
  config,
  inputs,
  hostname,
  adminUsername,
  ...
}:
let
  inherit (lib)
    mkIf
    utils
    mapAttrs
    filterAttrs
    isType
    optional
    mapAttrsToList
    optionalString
    mkForce
    concatStringsSep
    getExe
    ;
  inherit (config.modules.system) impermanence;
  cfg = config.modules.core;
  configDir = "/home/${adminUsername}/.config/nixos";

  rebuildCmds = [
    "switch"
    "test"
    "boot"
    "build"
    "dry-build"
    "dry-activate"
    "diff"
  ];

  rebuildScripts = map (
    cmd:
    pkgs.writeShellApplication {
      name = "rebuild-${cmd}";
      runtimeInputs = [ pkgs.nixos-rebuild ] ++ optional (cmd == "diff") pkgs.nvd;
      # Always rebuild in ~ because I once had a bad experience where I
      # accidentally built in /nix/store and caused irrepairable corruption

      # Use --fast on all switch modes apart from boot as I usually do a
      # rebuild-boot after a large nixpkgs change which is the only time when
      # --fast would be bad to use
      text = # bash
        ''
          flake="/home/${adminUsername}/.config/nixos"
          if [ ! -d $flake ]; then
            echo "Flake does not exist locally so using remote from github"
            flake="github:JManch/nixos"
          fi
          trap "popd >/dev/null 2>&1 || true" EXIT
          pushd ~ >/dev/null 2>&1

          nixos-rebuild ${if (cmd == "diff") then "build" else cmd} \
            --use-remote-sudo --flake "$flake#${hostname}" ${optionalString (cmd != "boot") "--fast"} "$@"
          ${optionalString (cmd == "diff") "nvd diff /run/current-system result"}
        '';
    }
  ) rebuildCmds;

  remoteRebuildScripts = map (
    cmd:
    let
      validation = # bash
        ''
          if [ "$#" = 0 ]; then
            echo "Usage: host-rebuild-${cmd} <hostname>"
            exit 1
          fi

          hostname=$1
          if [[ "$hostname" == "${hostname}" ]]; then
            echo "Error: Cannot ${cmd} remotely on local host"
            exit 1
          fi

          hosts=(${concatStringsSep " " (builtins.attrNames self.nixosConfigurations)})
          match=0
          for host in "''${hosts[@]}"; do
            if [[ $host = "$hostname" ]]; then
              match=1
              break
            fi
          done
          if [[ $match = 0 ]]; then
            echo "Error: Host '$hostname' does not exist" >&2
            exit 1
          fi

          flake="/home/${adminUsername}/.config/nixos"
          if [ ! -d $flake ]; then
            echo "Flake does not exist locally so using remote from github"
            flake="github:JManch/nixos"
          fi

          # Always build and store result to prevent GC deleting builds for remote hosts
          remote_builds="/home/${adminUsername}/.remote-builds/$hostname"
          mkdir -p "$remote_builds"
          trap "popd >/dev/null 2>&1 || true" EXIT
          pushd "$remote_builds" >/dev/null 2>&1
          nixos-rebuild build --flake "$flake#$hostname" ${optionalString (cmd != "boot") "--fast"} "''${@:2}"
        '';
    in
    pkgs.writeShellApplication {
      name = "host-rebuild-${cmd}";
      runtimeInputs = with pkgs; [
        nixos-rebuild
        openssh
        nvd
      ];
      text =
        validation
        + (
          if (cmd == "diff") then # bash
            ''
              if [ ! -d "${configDir}" ]; then
                echo "rebuild-diff requires the flake to exist locally in ${configDir}"
                exit 1
              fi

              remote_system=$(ssh "${adminUsername}@$hostname.lan" readlink /run/current-system)
              nixos_system=$(readlink "$remote_builds/result")
              nix-copy-closure --from "$hostname.lan" "$remote_system"
              nvd --color always diff "$remote_system" "$nixos_system"
            ''
          # bash
          else
            optionalString (cmd != "build") # bash
              ''
                nixos-rebuild ${cmd} ${optionalString (cmd != "boot") "--fast"} \
                  --use-remote-sudo --flake "$flake#$hostname" --target-host "root@$hostname.lan" "''${@:2}"
              ''
        );
    }
  ) rebuildCmds;

  setupSdImage = pkgs.writeShellApplication {
    name = "setup-sd-image";
    runtimeInputs = with pkgs; [
      parted
      age
    ];
    text = # bash
      ''
        if [ "$(id -u)" != "0" ]; then
           echo "This script must be run as root" 1>&2
           exit 1
        fi

        if [ "$#" -ne 2 ]; then
          echo "Usage: setup-sd-image <hostname> <result_path>"
          exit 1
        fi
        ${utils.exitTrapBuilder}

        hostname="$1"
        result="$2"

        flake="/home/${adminUsername}/.config/nixos"
        if [ ! -d $flake ]; then
          echo "Flake does not exist locally so using remote from github"
          flake="github:JManch/nixos"
        fi

        host_config="$flake#nixosConfigurations.$hostname.config"
        fs_type=$(nix eval --raw "$host_config.modules.hardware.fileSystem.type")
        username=$(nix eval --raw "$host_config.modules.core.username")
        admin_username=$(nix eval --raw "$host_config.modules.core.adminUsername")

        if [ "$fs_type" != "sd-image" ]; then
          echo "Host $hostname does not have a sd image filesystem" 1>&2
          exit 1
        fi

        tmpdir=$(mktemp -d)
        clean_up() {
          umount /mnt/nixos-sd-image >/dev/null 2>&1 || true
          rm -rf "$tmpdir"
        }
        add_exit_trap clean_up

        if ! ls "$result"/sd-image/*.img >/dev/null 2>&1; then
          echo "Result path does not contain an sd image" 1>&2
          exit 1
        fi

        echo "### Mounting sd image ###"
        cp "$result"/sd-image/*.img "$tmpdir"
        start_sector=$(parted -s "$tmpdir"/*.img unit s print 2>/dev/null | grep ext4 | awk '{print $2}' | sed 's/s//')
        offset=$((start_sector * 512))

        rootDir="/mnt/nixos-sd-image"
        mkdir -p $rootDir
        mount -o loop,offset="$offset" -t ext4 "$tmpdir"/*.img "$rootDir"

        echo "### Decrypting ssh-bootstrap-kit ###"
        temp_keys=$(mktemp -d)
        clean_up_keys() {
          rm -rf "$temp_keys"
        }
        add_exit_trap clean_up_keys
        kit_path="${../../../hosts/ssh-bootstrap-kit}"
        age -d "$kit_path" | tar -xf - -C "$temp_keys"

        echo "### Installing keys ###"
        install -d -m755 "$rootDir/etc/ssh" "$rootDir/home"
        install -d -m700 "$rootDir/home/$username" "$rootDir/home/$admin_username"
        install -d -m700 "$rootDir/home/$username/.ssh" "$rootDir/home/$admin_username/.ssh"

        # Host keys
        mv "$temp_keys/$hostname"/* "$rootDir/etc/ssh"

        # User keys
        if [ -d "$temp_keys/$username" ]; then
          mv "$temp_keys/$username"/* "$rootDir/home/$username/.ssh"
        fi

        # Admin user keys
        if [[ -d "$temp_keys/$admin_username" && -n "$(ls -A "$temp_keys/$admin_username")" ]]; then
          mv "$temp_keys/$admin_username"/* "$rootDir/home/$admin_username/.ssh"
        fi

        rm -rf "$temp_keys"
        # user:users
        chown -R 1000:100 "$rootDir/home/$username"

        if [ "$username" != "$admin_username" ]; then
          # admin_user:wheel
          chown -R 1:1 "$rootDir/home/$admin_username"
        fi

        umount "$rootDir"
        mv "$tmpdir"/*.img .
      '';
  };
in
{
  adminPackages = rebuildScripts ++ remoteRebuildScripts ++ [ setupSdImage ];
  persistenceAdminHome.directories = [ ".remote-builds" ];

  # Nice explanation of overlays: https://archive.is/f8goR
  #
  # My summary of the differences between overlays and `overrideAttrs`:
  #
  # Overlays modify the package derivation in nixpkgs whilst `overrideAttrs`
  # only modifies the package in the current context. In practice this means
  # that modifications made with overlays will apply to all instances of the
  # package throughout your entire configuration. If you want to modify a core
  # package that many modules and packages depend on, you can see how this is a
  # powerful feature. However, if not used carefully, overlays can trigger an
  # unwanted system-wide butterfly effect on package dependencies causing many
  # packages to be rebuilt from source. This is because modifying a package in
  # nixpkgs will result in all packages that depend on this package to have
  # their derivation modified and therefore their cache invalidated.
  #
  # `overrideAttrs` avoids this problem because the package is ONLY modified in
  # the context where you applied the override. This means that any dependent
  # packages will continue to use the unmodified version and will continue to
  # use the binary cache. If a module has a `package` option, this can be a
  # convenient place to apply the override as the package will be stored in the
  # option and can be easily reused elsewhere.
  #
  # In my experience, for the majority of packages that I'm overriding, only
  # overriding the package in the current context is sufficient. It has the
  # advantage of being more explicit than overlays and also guarantees no
  # unexpected dependency butterfly effects.
  #
  # Overlays allow for greater modifications to packages than `overrideAttrs`.
  # Literally anything is possible. The entire derivation can be replaced with
  # an entirely different package if desired. However, once again, in the vast
  # majority of cases this extra functionality is not required.
  #
  # To summarise, for the majority of situations where you want to modify a
  # package (using a different src, applying a patch etc...) overlays are NOT
  # necessary and `overrideAttrs` can be used instead. However depending on the
  # situation, overlays might be more convenient or required for their extra
  # functionality.
  nixpkgs = {
    overlays = [ ];
    config.allowUnfree = true;
  };

  nix =
    let
      flakeInputs = filterAttrs (_: isType "flake") inputs;
    in
    {
      channel.enable = false;
      daemonIOSchedClass = mkIf (!cfg.builder) "idle";
      daemonCPUSchedPolicy = mkIf (!cfg.builder) "idle";

      # Populates the nix registry with all our flake inputs `nix registry list`
      # Enables referencing flakes with short name in nix commands 
      # e.g. 'nix shell n#dnsutils' or 'nix shell hyprland#wlroots-hyprland'
      registry = (mapAttrs (_: flake: { inherit flake; }) flakeInputs) // {
        self.flake = inputs.self;
        n.flake = inputs.nixpkgs;
      };

      # Add flake inputs to nix path. Enables loading flakes with <flake_name>
      # like how <nixpkgs> can be referenced.
      nixPath = mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;

      settings = {
        experimental-features = [
          "flakes"
          "nix-command"
          "auto-allocate-uids"
        ];
        auto-optimise-store = true;
        # Do not create a bunch of nixbld users
        auto-allocate-uids = true;
        # Do not load the default global registry
        # https://channels.nixos.org/flake-registry.json
        flake-registry = "";
        trusted-users = [ adminUsername ];
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
        substituters = [ "https://nix-community.cachix.org" ];
        trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
      };

      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
    };

  system.autoUpgrade = mkIf cfg.autoUpgrade {
    enable = true;
    flake = "github:JManch/nixos";
    operation = "boot";
    dates = "daily";
    randomizedDelaySec = "2hours";
  };

  # Because one of our flake inputs is a private repo temporarily copy host ssh
  # keys so root uses them to authenticate with github
  systemd.services.nixos-upgrade.serviceConfig.ExecStart = mkForce (pkgs.writeShellScript "nixos-upgrade-ssh-auth" ''
    # Copy host ssh keys to /root/.ssh
    # Abort if /root.ssh exists
    if [ -d /root/.ssh ]; then
      echo "Aborting because root has ssh keys for some reason"
      exit 1
    fi
    mkdir -p /root/.ssh
    cp /etc/ssh/ssh_host_ed25519_key /root/.ssh/id_ed25519
    ${config.systemd.services.nixos-upgrade.script}
    rm -rf /root/.ssh
  '').outPath;

  # Sometimes nixos-rebuild compiles large pieces software that require more
  # space in /tmp than my tmpfs can provide. The obvious solution is to mount
  # /tmp to some actual storage. However, the majority of my rebuilds do not
  # need the extra space and I'd like to avoid the extra disk wear. By using a
  # custom tmp directory for nix builds, I can bind mount the build dir to
  # persistent storage when I know the build will be large. This wouldn't be
  # possible with the standard /tmp dir because bind mounting /tmp on a running
  # system would break things.
  # Relevant github issue: https://github.com/NixOS/nixpkgs/issues/54707

  # NOTE: When nix updates to 2.23, replace this with the new build-dir conf
  # https://hydra.nixos.org/build/263397466/download/1/manual/command-ref/conf-file.html?highlight=build-dir#conf-build-dir

  # List of programs that require the bind mount to compile:
  # - mongodb
  systemd.services.nix-daemon.environment.TMPDIR = mkIf impermanence.enable "/var/nix-tmp";
  systemd.tmpfiles.rules = mkIf impermanence.enable [
    "d /var/nix-tmp 0755 root root"
    "d /persist/var/nix-tmp 0755 root root"
  ];

  programs.zsh = {
    interactiveShellInit = # bash
      ''
        inspect-host() {
          if [ -z "$1" ]; then
            echo "Usage: inspect-host <hostname>"
            return 1
          fi
          nixos-rebuild repl --flake "${configDir}#$1"
        }

        build-installer() {
          if [ -z "$1" ]; then
            echo "Usage: build-installer <name>"
            return 1
          fi

          flake="/home/${adminUsername}/.config/nixos"
          if [ ! -d $flake ]; then
            echo "Flake does not exist locally so using remote from github"
            flake="github:JManch/nixos"
          fi

          host_config="$flake#nixosConfigurations.$1.config"
          fs_type=$(nix eval --raw "$host_config.modules.hardware.fileSystem.type")
          result=$(nix build "$flake#installer-$1")
          if [ "$fs_type" = "sd-image"]; then
            sudo ${getExe setupSdImage} "$1" "$result"
          fi
        }
      '';

    shellAliases = {
      mount-nix-tmp = mkIf impermanence.enable "sudo mount --bind /persist/var/nix-tmp /var/nix-tmp";
      system-size = "nix path-info --closure-size --human-readable /run/current-system";
    };
  };
}
