{
  ns,
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (secrets.general) people userIds devices;
  inherit (lib)
    mkOption
    types
    concatMapStringsSep
    splitString
    replaceStrings
    removeAttrs
    singleton
    sortOn
    ;
  secrets = inputs.nix-resources.secrets.hass { inherit lib config; };
  cfg = config.${ns}.services.hass;
in
{
  options.${ns}.services.hass.rooms = mkOption {
    description = ''
      Attribute set of rooms where the name is the home assistant room ID and
      the value is the configuration of features for the room.
    '';
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }:
        {
          options = {
            person = mkOption {
              type = types.str;
              description = "Room owner";
            };

            formattedRoomName = mkOption {
              default = concatMapStringsSep " " (s: lib.${ns}.upperFirstChar s) (splitString "_" name);
              readOnly = true;
              example = "Joshua Room";
            };

            deviceId = mkOption {
              type = types.nullOr types.str;
              readOnly = true;
              default = devices.${config.person}.name;
              description = "Mobile device belonging to the room owner";
            };

            sensors = {
              temperature = mkOption {
                type = types.str;
                example = "joshua_sensor_temperature";
                description = "Entity ID of numeric temperature sensor in the room";
              };

              humidity = mkOption {
                type = types.str;
                example = "joshua_sensor_humidity";
                description = "Entity ID of numeric humidity sensor in the room";
              };
            };

            lovelace = {
              dashboard = mkOption {
                type = types.attrs;
                readOnly = true;
                default = {
                  title = config.formattedRoomName;
                  path = replaceStrings [ "_" ] [ "-" ] name;
                  type = "sections";
                  max_columns = 2;
                  subview = true;
                  sections = config.lovelace.sections;
                };
              };

              sections = mkOption {
                type = types.listOf (
                  types.submodule {
                    freeformType = with types; attrsOf anything;
                    options = {
                      priority = mkOption {
                        type = types.int;
                        description = "Priority of the section";
                      };

                      title = mkOption {
                        type = types.str;
                        description = "Title of the section";
                      };

                      cards = mkOption {
                        type = with types; listOf attrs;
                        default = [ ];
                        description = "Cards in the section";
                      };
                    };
                  }
                );
                default = [ ];
                apply =
                  sections:
                  let
                    sorted = sortOn (section: section.priority) sections;
                  in
                  map (section: removeAttrs section [ "priority" ]) sorted;
              };
            };
          };
        }
      )
    );
  };

  config = {
    ${ns}.services.hass.rooms = {
      joshua_room = {
        person = "joshua";

        sensors = {
          temperature = "joshua_sensor_temperature";
          humidity = "joshua_sensor_humidity";
        };

        airConditioning = {
          enable = true;
          climateId = "joshua_faikin_mqtt_hvac";
        };

        dehumidifier = {
          enable = true;
          switchId = "joshua_dehumidifier";
          calibrationFactor = 1.754;
        };

        sleepTracking = {
          enable = true;
          useAlarm = true;
        };

        lighting = {
          enable = true;
          wakeUpLights.enable = true;

          individualLights = [
            "joshua_lamp_floor"
            "joshua_lamp_bed"
            "joshua_bulb_ceiling"
            "joshua_play_desk_1"
            "joshua_play_desk_2"
          ];

          adaptiveLighting = {
            enable = true;
            sleepMode = {
              automate = true;
              disabledLights = [ "light.joshua_bulb_ceiling" ];
            };
          };

          automatedToggle = {
            enable = true;
            presenceTriggers = singleton {
              platform = "state";
              entity_id = "binary_sensor.ncase_m1_active";
              from = null;
            };

            presenceConditions = singleton {
              condition = "state";
              entity_id = "binary_sensor.ncase_m1_active";
              state = "on";
            };

            noPresenceConditions = singleton {
              condition = "state";
              entity_id = "binary_sensor.ncase_m1_active";
              state = "off";
            };
          };
        };

        bedWarmer = {
          enable = true;
          switchId = "joshua_bed_warmer";
        };

        lovelace.sections = singleton {
          title = "Devices";
          priority = 10;
          type = "grid";
          cards = singleton {
            type = "history-graph";
            entities = [ { entity = "binary_sensor.ncase_m1_active"; } ];
            hours_to_show = 24;
          };
          visibility = singleton {
            condition = "user";
            users = [ userIds.joshua ];
          };
        };
      };

      lounge = {
        lighting = {
          enable = true;
          adaptiveLighting = {
            enable = true;
            takeOverControl = true;
            minBrightness = 50;
          };
          floorPlan = {
            enable = true;
            lights =
              let
                inherit (cfg.rooms.lounge.lighting.floorPlan) mkFloorPlanLight;
              in
              [
                (mkFloorPlanLight "lounge_spot_ceiling_1" 85 65)
                (mkFloorPlanLight "lounge_spot_ceiling_2" 85 25)
                (mkFloorPlanLight "lounge_spot_ceiling_3" 72 45)
                (mkFloorPlanLight "lounge_spot_ceiling_4" 59 65)
                (mkFloorPlanLight "lounge_spot_ceiling_5" 59 25)
                (mkFloorPlanLight "lounge_spot_ceiling_6" 39 65)
                (mkFloorPlanLight "lounge_spot_ceiling_7" 39 25)
                (mkFloorPlanLight "lounge_spot_ceiling_8" 26 45)
                (mkFloorPlanLight "lounge_spot_ceiling_9" 13 65)
                (mkFloorPlanLight "lounge_spot_ceiling_10" 13 25)
              ];
          };
        };

        underfloorHeating = {
          enable = true;
          climateId = "lounge_underfloor_heating";
        };

        lovelace.sections = singleton {
          title = "Devices";
          priority = 10;
          type = "grid";
          cards = [
            {
              type = "tile";
              entity = "vacuum.roborock_s6_maxv";
              layout_options = {
                grid_columns = 4;
                grid_rows = 2;
              };
              features = singleton {
                type = "vacuum-commands";
                commands = [
                  "start_pause"
                  "stop"
                  "clean_spot"
                ];
              };
            }
            {
              type = "media-control";
              entity = "media_player.lounge_tv";
            }
          ];
        };
      };

      study = {
        sensors = {
          temperature = "study_ac_climatecontrol_room_temperature";
          humidity = "study_ac_climatecontrol_room_humidity";
        };

        lighting = {
          enable = true;
          basicLights = true;
          floorPlan = {
            enable = true;
            lights =
              let
                inherit (cfg.rooms.study.lighting.floorPlan) mkFloorPlanLight;
              in
              [
                (mkFloorPlanLight "study_spot_ceiling_1" 78 52)
                (mkFloorPlanLight "study_spot_ceiling_2" 48 52)
                (mkFloorPlanLight "study_spot_ceiling_3" 48 20)
                (mkFloorPlanLight "study_spot_ceiling_4" 25 70)
                (mkFloorPlanLight "study_spot_ceiling_5" 25 40)
              ];
          };
        };

        airConditioning = {
          enable = true;
          climateId = "study_ac_room_temperature";
        };
      };

      master_bedroom = {
        sensors = {
          temperature = "master_ac_climatecontrol_room_temperature";
          humidity = "master_ac_climatecontrol_room_humidity";
        };

        airConditioning = {
          enable = true;
          climateId = "master_ac_room_temperature";
        };
      };

      "${people.person1}_room" =
        let
          person = people.person1;
        in
        {
          inherit person;

          sensors = {
            temperature = "${person}_ac_climatecontrol_room_temperature";
            humidity = "${person}_ac_climatecontrol_room_humidity";
          };

          airConditioning = {
            enable = true;
            climateId = "${person}_ac_room_temperature";
          };

          underfloorHeating = {
            enable = true;
            climateId = "${person}_underfloor_heating";
          };

          sleepTracking.enable = true;

          lighting = {
            enable = true;
            wakeUpLights.enable = true;

            adaptiveLighting = {
              enable = true;
              sleepMode.automate = true;
            };
          };
        };

      "${people.person2}_room" =
        let
          person = people.person2;
        in
        {
          inherit person;

          sleepTracking = {
            enable = true;
            useAlarm = true;
          };

          sensors = {
            temperature = "${person}_ac_climatecontrol_room_temperature";
            humidity = "${person}_ac_climatecontrol_room_humidity";
          };

          airConditioning = {
            enable = true;
            climateId = "${person}_ac_room_temperature";
          };

          lighting = {
            enable = true;
            wakeUpLights.enable = true;

            adaptiveLighting = {
              enable = true;
              sleepMode.automate = true;
              sleepMode.color = [
                255
                0
                0
              ];
            };
          };
        };

      "${people.person3}_room" =
        let
          person = people.person3;
        in
        {
          inherit person;

          sleepTracking = {
            enable = true;
            useAlarm = true;
          };

          sensors = {
            temperature = "${person}_ac_climatecontrol_room_temperature";
            humidity = "${person}_ac_climatecontrol_room_humidity";
          };

          airConditioning = {
            enable = true;
            climateId = "${person}_ac_room_temperature";
          };

          lighting = {
            enable = true;
            wakeUpLights.enable = true;

            floorPlan = {
              enable = true;
              lights =
                let
                  inherit (cfg.rooms.study.lighting.floorPlan) mkFloorPlanLight;
                in
                [
                  (mkFloorPlanLight "${person}_spot_ceiling_1" 75 75)
                  (mkFloorPlanLight "${person}_spot_ceiling_2" 75 25)
                  (mkFloorPlanLight "${person}_spot_ceiling_3" 50 50)
                  (mkFloorPlanLight "${person}_spot_ceiling_4" 25 75)
                  (mkFloorPlanLight "${person}_spot_ceiling_5" 25 25)
                ];
            };

            adaptiveLighting = {
              enable = true;
              sleepMode = {
                automate = true;
                color = [
                  255
                  0
                  0
                ];
                disabledLights = [
                  "light.${person}_spot_ceiling_3"
                  "light.${person}_spot_ceiling_4"
                  "light.${person}_spot_ceiling_5"
                ];
              };
            };
          };
        };
    };
  };
}