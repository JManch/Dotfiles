{ lib
, pkgs
, config
, username
, ...
} @ args:
let
  inherit (lib) mkIf mkMerge mkVMOverride mod getExe optionals;
  cfg = config.modules.system.virtualisation;
in
mkMerge [
  {
    # We configure the vmVariant regardless of whether or not the host has
    # virtualisation enabled because it should be possible to create a VM of any host
    virtualisation.vmVariant = {
      device = mkVMOverride {
        monitors = [{
          name = "Virtual-1";
          number = 1;
          refreshRate = 60.0;
          width = 2048;
          height = 1152;
          position = "0x0";
          workspaces = [ 1 2 3 4 5 6 7 8 9 ];
        }];
        gpu.type = null;
      };

      modules = {
        system = {
          bluetooth.enable = mkVMOverride false;
          audio.enable = mkVMOverride false;
          virtualisation.enable = mkVMOverride false;

          networking = {
            tcpOptimisations = mkVMOverride false;
            wireless.enable = mkVMOverride false;
            firewall.enable = mkVMOverride false;
          };
        };
      };

      virtualisation =
        let
          desktopEnabled = config.usrEnv.desktop.enable;
        in
        {
          # TODO: Make this modular based on host spec. Ideally would base this
          # on the host we are running the VM on but I don't think that's
          # possible? Could be logical to simulate the exact specs of the host
          # we are replicating, although that won't always be feasible
          # depending the actual host we are running the vm on. Could work
          # around this by instead modifying the generated launch script in our
          # run-vm zsh function.
          # We can solve this by storing the currents hosts specs in env vars.
          memorySize = 4096;
          cores = 8;
          graphics = desktopEnabled;
          qemu = {
            options = optionals desktopEnabled [
              # Allows nixos-rebuild build-vm graphical session
              # https://github.com/NixOS/nixpkgs/issues/59219
              "-device virtio-vga-gl"
              "-display gtk,show-menubar=off,gl=on"
            ];
          };
          # Forward all TCP and UDP ports that are opened in the firewall on
          # the default interfaces. Should make the majority of the VMs
          # services accessible from host
          # TODO: Add a "vmVariant.firewallInterfaces" option that lists
          # interfaces to expose from the VM variant. Might need to remove
          # duplicate ports, not sure if it's an issue to open same port
          # multiple times?
          forwardPorts =
            let
              # It's important to use firewall rules from the vmVariant here
              inherit (config.virtualisation.vmVariant.networking.firewall)
                allowedTCPPorts
                allowedUDPPorts;
              inherit (config.virtualisation.vmVariant.modules.system.virtualisation)
                mappedTCPPorts
                mappedUDPPorts;

              forward = proto: mapped: port: {
                from = "host";
                # If not mapped, attempt to map host port to a unique value between 50000-65000
                host = {
                  port = if mapped then port.hostPort else (mod port 15001) + 50000;
                  address = "127.0.0.1";
                };
                guest.port = if mapped then port.vmPort else port;
                proto = proto;
              };
            in
            map (forward "tcp" false) allowedTCPPorts
            ++
            map (forward "udp" false) allowedUDPPorts
            ++
            map (forward "tcp" true) mappedTCPPorts
            ++
            map (forward "udp" true) mappedUDPPorts;
        };
    };
  }

  (mkIf cfg.enable {
    programs.virt-manager.enable = true;
    users.users.${username}.extraGroups = [ "libvirtd" "docker" ];

    hm.dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };

    virtualisation = {
      libvirtd.enable = true;
      # TODO: Properly configure docker
      docker.enable = false;
    };

    programs.zsh.interactiveShellInit =
      let
        inherit (lib) utils;
        inherit (homeConfig.modules.desktop) terminal;
        homeConfig = utils.homeConfig args;
        grep = getExe pkgs.gnugrep;
        sed = getExe pkgs.gnused;
      in
        /*bash*/ ''

        run-vm() {
          if [ -z "$1" ]; then
            echo "Usage: build-vm <hostname>"
            return 1
          fi

          # Build the VM
          runscript="/home/${username}/result/bin/run-$1-vm"
          cd && sudo nixos-rebuild build-vm --flake /home/${username}/.config/nixos#$1
          if [ $? -ne 0 ]; then return 1; fi

          # Print ports mapped to the VM
          echo "\nMapped Ports:\n$(${grep} -o 'hostfwd=[^,]*' $runscript | ${sed} 's/hostfwd=//g')"

          # For non-graphical VMs, launch VM and start ssh session in new
          # terminal windows
          if grep -q -- "-nographic" "$runscript"; then
            ${if config.usrEnv.desktop.enable then /*bash*/ ''
              ${terminal.exePath} -e "zsh" "-i" "-c" "ssh-vm; zsh -i" &
              ${terminal.exePath} --class qemu -e $runscript
            ''
            else "$runscript"}
          else
            $runscript
          fi
        }

        ssh-vm() {
          ssh-add-quiet
          echo "Attempting SSH connection to VM..."; 
          # Extra connection attempts as VM may be starting up
          ssh \
            -o "StrictHostKeyChecking=no" \
            -o "UserKnownHostsFile=/dev/null" \
            -o "LogLevel=QUIET" \
            -o "ConnectionAttempts 30" \
            ${username}@127.0.0.1 -p 50022;
        }

      '';

    persistence.directories = [ "/var/lib/libvirt" ];
  })
]
