{pkgs, ...}: {
  programs.firefox.enable = true;
  programs.firefox.package = pkgs.firefox-esr;
  programs.firefox.policies = {
    SearchEngines = {
      Default = "SearX";
      Remove = [
        "Google"
        "Bing"
        "Amazon.com"
        "eBay"
        "Wikipedia"
      ];
      Add = [
        {
          Name = "SearX";
          URLTemplate = "https://search.trexd.dev/search?q={searchTerms}";
          Method = "GET";
          IconURL = "https://search.trexd.dev/favicon.ico";
          SuggestURLTemplate = "https://search.trexd.dev/autocompleter?q={searchTerms}";
        }
      ];
    };
  };
}
