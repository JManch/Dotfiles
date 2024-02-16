{ lib, config, osConfig, ... }:
let
  cfg = config.modules.programs.mangohud;
  device = osConfig.device;
  colors = config.colorscheme.palette;
in
lib.mkIf cfg.enable {
  programs.mangohud = {
    enable = true;
    settings = {
      # Performance
      fps_limit = "0,60,144,165";
      show_fps_limit = true;

      # UI
      legacy_layout = 0;
      no_display = true; # Whether to hide the HUD by default
      font_size = 20;
      round_corners = "${toString config.modules.desktop.style.cornerRadius}";
      hud_compact = true;
      text_color = "${colors.base07}";
      gpu_color = "${colors.base08}";
      cpu_color = "${colors.base09}";
      vram_color = "${colors.base0E}";
      ram_color = "${colors.base0C}";
      engine_color = "${colors.base0F}";
      io_color = "${colors.base0D}";
      frametime_color = "${colors.base0B}";
      background_color = "${colors.base00}";

      # GPU
      vram = true;
      gpu_stats = true;
      gpu_temp = true;
      gpu_mem_temp = true;
      gpu_junction_temp = true;
      gpu_core_clock = true;
      gpu_mem_clock = true;
      gpu_power = true;
      gpu_text = device.gpu.name;
      gpu_load_change = true;
      gpu_fan = true;
      gpu_voltage = true;
      gpu_load_color = "${colors.base0B},${colors.base0A},${colors.base08}";
      # Throttling stats are misleading with 7900xt
      throttling_status = false;

      # CPU
      cpu_stats = true;
      cpu_temp = true;
      cpu_power = true;
      cpu_text = device.cpu.name;
      cpu_mhz = true;
      cpu_load_change = true;
      cpu_load_color = "${colors.base0B},${colors.base0A},${colors.base08}";

      # IO
      io_read = true;
      io_write = true;

      # System
      ram = true;
      vulkan_driver = true;
      gamemode = true;
      resolution = true;

      # FPS
      fps = true;
      fps_color = "${colors.base0B},${colors.base0A},${colors.base08}";
      frametime = true;
      frame_timing = true;
      histogram = true;
      # fps_metrics = "avg,0.01"; # need to wait for new stable version

      # Gamescope
      fsr = true;
      # refresh_rate = true; # need to wait for new stable version

      # Bindings
      toggle_fps_limit = "Shift_L+F1";
      toggle_hud = "Shift_R+F12";
      toggle_preset = "Shift_R+F10";
      toggle_hud_position = "Shift_R+F11";
      toggle_logging = "Shift_L+F2";
      reload_cfg = "Shift_L+F4";
    };
  };
}
