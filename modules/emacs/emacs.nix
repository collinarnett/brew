{pkgs, ...}: {
  environment.systemPackages = [
    (pkgs.emacsWithPackagesFromUsePackage {
      config = ./emacs.el;
      alwaysEnsure = true;
      defaultInitFile = true;
      package = pkgs.emacs-unstable;
      extraEmacsPackages = epkgs:
        with epkgs; [
          use-package
          (treesit-grammars.with-grammars
            (grammars:
              with grammars; [
                tree-sitter-bash
                tree-sitter-scala
                tree-sitter-commonlisp
                tree-sitter-elisp
                tree-sitter-haskell
                tree-sitter-c
                tree-sitter-java
                tree-sitter-go
                tree-sitter-zig
                tree-sitter-nix
              ]))
        ];
    })
  ];
}
