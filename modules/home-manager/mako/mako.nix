{...}: {
  services.mako = {
    enable = true;
    extraConfig = builtins.toString ./config;
  };
}
