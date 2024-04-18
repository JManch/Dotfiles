{ lib
, pkgs
, config
, osConfig
, ...
}:
let
  inherit (lib) mkIf mapAttrs getExe concatStringsSep attrNames take drop;
  cfg = config.modules.desktop.services.darkman;

  colorSchemeSwitchingConfiguration =
    let
      inherit (config.modules.colorScheme) colorMap;
      inherit (config.xdg) configHome;
      inherit (lib.hm.dag) entryAfter entryBetween;
      sed = getExe pkgs.gnused;
      baseColors = attrNames colorMap;

      genVariants = { paths, format ? c: c, colors ? colorMap, ... }: concatStringsSep "\n" (map
        (path:
          let
            sedCommand = /*bash*/ ''
              # Replacement have to be done over three commands to avoid cycles
              ${sed} ${concatStringsSep " " (
                # Replace first four colors with their base name
                map (base: "-e 's/${format colors.${base}.dark}/${base}/g'")
                (take 4 baseColors)
              )} "${configHome}/${path}" | \
              \
              ${sed} ${concatStringsSep " " (
                # Replace all but the first 4 colors with their light variant
                map (base: "-e 's/${format colors.${base}.dark}/${format colors.${base}.light}/g'")
                (drop 4 baseColors)
              )} | \
              \
              ${sed} ${concatStringsSep " " (
                # Replace the first 4 base names with their light variant
                map (base: "-e 's/${base}/${format colors.${base}.light}/g'")
                (take 4 baseColors)
              )} > "${configHome}/${path}.light"
            '';
          in
            /*bash*/ ''

            run --quiet install -m644 "${configHome}/${path}" "${configHome}/${path}.dark"

            if [[ -v DRY_RUN ]]; then
              cat <<EOF
                ${sedCommand}
            EOF
            else
              ${sedCommand}
            fi

            if [ "$(${getExe config.services.darkman.package} get)" = "light" ]; then
              run --quiet rm -f "${configHome}/${path}"
              run --quiet cp "${configHome}/${path}.light" "${configHome}/${path}"
            fi

          '')
        paths);

      deleteArtifacts = paths: concatStringsSep "\n" (map
        (path: /*bash*/ ''
          run --quiet rm -f "${configHome}/${path}" "${configHome}/${path}.homemanagerbak"
        '')
        paths
      );

      switchScript = { paths, theme }: concatStringsSep "\n" (map
        (path: /*bash*/ ''
          rm -f "${configHome}/${path}" "${configHome}/${path}.homemanagerbak"
          cp "${configHome}/${path}.${theme}" "${configHome}/${path}"
        '')
        paths);
    in
    {
      home.activation."delete-darkman-artifacts" = entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        ${concatStringsSep "\n" (
          map (app: deleteArtifacts cfg.switchApps.${app}.paths)
          (attrNames cfg.switchApps)
        )}
      '';

      home.activation."generate-darkman-variants" = entryAfter [ "linkGeneration" ] ''
        ${concatStringsSep "\n" (
          map (app: genVariants cfg.switchApps.${app})
          (attrNames cfg.switchApps)
        )}
      '';

      modules.desktop.services.darkman.switchScripts = mapAttrs
        (_: value:
          (theme: ''
            ${switchScript { inherit (value) paths; inherit theme;}}
            ${value.reloadScript or ""}
          '')
        )
        cfg.switchApps;
    };
in
{
  config = mkIf (cfg.enable && osConfig.usrEnv.desktop.enable) ({
    services.darkman = {
      enable = true;
      package = pkgs.darkman.override {
        buildGoModule = args: pkgs.buildGoModule (args // rec {
          version = "2024-04-18";
          patches = [ ../../../../../patches/darkman.diff ];

          src = pkgs.fetchFromGitLab {
            owner = "WhyNotHugo";
            repo = "darkman";
            rev = "57d1bfd417b0810da919fe5cbfee384addc74f2c";
            sha256 = "sha256-MOhqlxC0aQz1692iiJUlaug9RfDyIJPnzw+4/O+2LZI=";
          };

          ldflags = [
            "-X main.Version=${version}"
            "./cmd/darkman"
          ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp darkman $out/bin
            runHook postInstall
          '';

          vendorHash = "sha256-3lILSVm7mtquCdR7+cDMuDpHihG+gDJTcQa1cM2o7ZU=";
        });
      };
      darkModeScripts = mapAttrs (_: v: v "dark") cfg.switchScripts;
      lightModeScripts = mapAttrs (_: v: v "light") cfg.switchScripts;

      settings = {
        lat = 50.8;
        lng = -0.1;
        usegeoclue = false;
      };
    };

    # Causes portal to crash, not sure if this is a darkman problem or xdg
    # portal?
    # xdg.portal.config.common = {
    #   "org.freedesktop.impl.portal.Settings" = [ "darkman" ];
    # };

  } // colorSchemeSwitchingConfiguration);
}