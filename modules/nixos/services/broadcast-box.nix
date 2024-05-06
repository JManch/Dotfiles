{ lib, config, inputs, ... }:
let
  inherit (lib) mkIf mkForce optional;
  inherit (inputs.nix-resources.secrets) fqDomain;
  inherit (config.modules.services) wireguard;
  cfg = config.modules.services.broadcast-box;
in
{
  imports = [
    inputs.broadcast-box.nixosModules.default
  ];

  disabledModules = [
    "${inputs.nixpkgs}/nixos/modules/services/video/broadcast-box.nix"
  ];

  services.broadcast-box = {
    enable = true;
    http.port = cfg.port;
    udpMux.port = cfg.udpMuxPort;
    # This breaks local streaming without hairpin NAT so hairpin NAT is needed
    # for streaming from local network when proxying
    nat.autoConfigure = cfg.proxy;
    statusAPI = !cfg.proxy;
  };

  systemd.services.broadcast-box.wantedBy = mkForce (
    optional cfg.autoStart "multi-user.target"
  );

  # When not proxying only expose over wg interface
  networking.firewall.interfaces.wg-friends = mkIf (wireguard.friends.enable && !cfg.proxy) {
    allowedTCPPorts = [ cfg.port ];
    allowedUDPPorts = [ cfg.udpMuxPort ];
  };

  modules.system.networking.publicPorts = [ cfg.udpMuxPort ];
  networking.firewall.allowedUDPPorts = mkIf cfg.proxy [ cfg.udpMuxPort ];

  services.caddy.virtualHosts."stream.${fqDomain}".extraConfig = mkIf cfg.proxy ''
    reverse_proxy http://127.0.0.1:${toString cfg.port}
  '';
}
