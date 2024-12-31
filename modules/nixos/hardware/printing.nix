{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    ns
    mkIf
    mkMerge
    mkForce
    mkBefore
    singleton
    getExe'
    ;
  inherit (config.${ns}.services) caddy;
  cfg = config.${ns}.hardware.printing;

  dcp9015cdwlpr = pkgs.dcp9020cdwlpr.overrideAttrs (oldAttrs: rec {
    pname = "dcp9015cdw-lpr";
    version = "1.1.3";
    src = pkgs.fetchurl {
      url = "https://download.brother.com/welcome/dlf102113/dcp9015cdwlpr-${version}-0.i386.deb";
      sha256 = "sha256-ySywvrQ51dBMwnKP6IgDW06u560us2K+5ls1gSJB1+c=";
    };
    installPhase = lib.replaceStrings [ "dcp9020cdw" ] [ "dcp9015cdw" ] oldAttrs.installPhase;
  });

  dcp9015cdw-cupswrapper = pkgs.dcp9020cdw-cupswrapper.overrideAttrs (oldAttrs: rec {
    pname = "dcp9015cdw-cupswrapper";
    version = "1.1.4";
    src = pkgs.fetchurl {
      url = "https://download.brother.com/welcome/dlf102114/dcp9015cdwcupswrapper-${version}-0.i386.deb";
      sha256 = "sha256-QUSILXzr2M+huvgXUc1UPpM/C/QoNo5PFUuy3via3EA=";
    };
    installPhase = lib.replaceStrings [ "dcp9020cdw" ] [ "dcp9015cdw" ] oldAttrs.installPhase;
  });
in
mkMerge [
  (mkIf cfg.client.enable {
    services.printing.enable = true;

    hardware.printers = {
      ensurePrinters = [
        {
          name = "Brother-DCP-9015CDW";
          deviceUri = "ipp://${cfg.client.serverAddress}/printers/Brother-DCP-9015CDW";
          model = "everywhere";
          ppdOptions.PageSize = "A4";
        }
      ];
      ensureDefaultPrinter = "Brother-DCP-9015CDW";
    };
  })

  (mkIf cfg.server.enable {
    assertions = lib.${ns}.asserts [
      caddy.enable
      "Printing server requires Caddy to be enabled"
      (config.${ns}.device.type == "server")
      "Printing server can only be run on servers on secure local networks"
    ];

    services.printing = {
      enable = true;
      openFirewall = true;
      stateless = true;
      # Doesn't work well with stateless because previously configured printers
      # gets removed everytime the service starts with this enabled
      startWhenNeeded = false;
      defaultShared = true;
      listenAddresses = [ "*:631" ];

      drivers = [
        dcp9015cdwlpr
        dcp9015cdw-cupswrapper
      ];

      # WARN: This is an insecure config that gives anyone on the local network
      # full access to printer operations. Only use on secure networks.
      # Admin auth should be done through the https reverse proxy.
      extraConf = mkForce ''
        ServerAlias *
        DefaultEncryption Never
        DefaultAuthType None

        <Location />
          Order allow,deny
          Allow from all
        </Location>

        <Location /admin>
          Order allow,deny
          Allow localhost
        </Location>

        <Location /admin/conf>
          AuthType Basic
          Require user @SYSTEM
          Order allow,deny
          Allow localhost
        </Location>

        <Policy default>
          <Limit All>
            Order deny,allow
            Allow from all
          </Limit>
        </Policy>
      '';
    };

    # Keep an eye on this for https://github.com/NixOS/nixpkgs/issues/78535
    hardware.printers = {
      ensureDefaultPrinter = "Brother-DCP-9015CDW";

      ensurePrinters = singleton {
        name = "Brother-DCP-9015CDW";
        deviceUri = "ipp://printer.lan/ipp/print";
        model = "everywhere";
        ppdOptions.PageSize = "A4";
      };
    };

    ${ns}.services.caddy.virtualHosts.printing.extraConfig = ''
      reverse_proxy http://localhost:631 {
        header_up host localhost
      }
    '';
  })

  (mkIf (cfg.client.enable || cfg.server.enable) {
    # We customise the service so that it runs every hour instead of once at
    # boot. The script aborts if the printer is down or has already been
    # configured. This way the printer gets configured even if it sometimes
    # goes offline.
    systemd.services.ensure-printers = {
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = mkForce [ ];
      requires = [ "nss-lookup.target" ];
      startAt = if cfg.server.enable then "*-*-* *:00:00" else "*-*-* *:05:00";

      script =
        mkBefore
          # bash
          ''
            if ! ${getExe' pkgs.iputils "ping"} -c 1 -W 1 "printer.lan" &>/dev/null; then
              echo "Cannot setup printer. Host is down."
              exit 0
            fi

            if ${getExe' pkgs.cups "lpstat"} -p ${config.hardware.printers.ensureDefaultPrinter} &>/dev/null; then
              echo "Printer already configured."
              exit 0
            fi
          '';
    };
  })
]
