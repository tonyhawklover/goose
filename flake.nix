{
  description = "Dev environment for Goose, an open-source iOS distraction-blocking app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      # Nix can't ship Apple's SDKs or signing tools, so these wrap the
      # installed Xcode's xcodebuild.
      mkApp = pkgs: name: runtimeInputs: text: {
        type = "app";
        program = "${pkgs.writeShellApplication {
          inherit name runtimeInputs text;
        }}/bin/${name}";
      };
    in
    {
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          name = "goose-ios";
          buildInputs = [
            pkgs.xcbeautify
            pkgs.swiftlint
            pkgs.ios-deploy
          ];
          shellHook = ''
            echo "goose-ios dev shell ready."
            echo "  nix run .#build-sim     - build for the iOS Simulator"
            echo "  nix run .#build-device  - build for a physical iPhone (validates signing)"
            echo "  nix run .#run-sim       - build, install, and launch once in the Simulator"
            echo "  nix run .#test          - run the unit tests in the Simulator"
            echo "  nix run .#watch         - like run-sim, but re-runs itself on every .swift save"
            echo ""
            echo "NFC scanning and Screen Time app-blocking only work on a real iPhone,"
            echo "not the Simulator. Use Xcode itself (Cmd+R with your iPhone selected)"
            echo "for the real thing. Set your Team ID and bundle ID in Config/Local.xcconfig first."
            echo "The Screen Time permission dialog no longer appears in the Simulator"
            echo "(AppBlocker skips it there; see the targetEnvironment(simulator) guard)."
          '';
        };
      });

      apps = forEachSystem (pkgs: {
        build-sim = mkApp pkgs "build-sim" [ pkgs.xcbeautify ] ''
          xcodebuild \
            -project Goose.xcodeproj \
            -scheme Goose \
            -destination 'generic/platform=iOS Simulator' \
            -configuration Debug \
            build | xcbeautify
        '';

        build-device = mkApp pkgs "build-device" [ pkgs.xcbeautify ] ''
          xcodebuild \
            -project Goose.xcodeproj \
            -scheme Goose \
            -destination 'generic/platform=iOS' \
            -configuration Debug \
            -allowProvisioningUpdates \
            build | xcbeautify
        '';

        # Signing is off, so no Config/Local.xcconfig is needed. Same as CI.
        test = mkApp pkgs "test" [ pkgs.xcbeautify ] ''
          SIM_NAME="''${SIM_NAME:-iPhone 17}"

          xcodebuild test \
            -project Goose.xcodeproj \
            -scheme Goose \
            -destination "platform=iOS Simulator,name=$SIM_NAME" \
            CODE_SIGNING_ALLOWED=NO | xcbeautify
        '';

        run-sim = mkApp pkgs "run-sim" [ pkgs.xcbeautify ] ''
          SIM_NAME="''${SIM_NAME:-iPhone 17}"

          xcodebuild \
            -project Goose.xcodeproj \
            -scheme Goose \
            -destination "platform=iOS Simulator,name=$SIM_NAME" \
            -configuration Debug \
            build | xcbeautify

          APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/Goose.app" -print -quit)
          if [ -z "$APP_PATH" ]; then
            echo "Could not locate built Goose.app in DerivedData" >&2
            exit 1
          fi

          BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist")
          xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
          open -a Simulator
          xcrun simctl terminate "$SIM_NAME" "$BUNDLE_ID" 2>/dev/null || true
          xcrun simctl install "$SIM_NAME" "$APP_PATH"
          xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID"
        '';

        # Rebuilds and relaunches in the Simulator on every save under Goose/.
        watch = mkApp pkgs "watch" [ pkgs.xcbeautify pkgs.fswatch ] ''
          SIM_NAME="''${SIM_NAME:-iPhone 17}"

          rebuild() {
            echo "── rebuilding ($(date '+%H:%M:%S')) ──"
            if ! xcodebuild \
              -project Goose.xcodeproj \
              -scheme Goose \
              -destination "platform=iOS Simulator,name=$SIM_NAME" \
              -configuration Debug \
              build | xcbeautify; then
              echo "── build failed, still watching ──"
              return 0
            fi

            APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/Goose.app" -print -quit)
            if [ -z "$APP_PATH" ]; then
              echo "Could not locate built Goose.app in DerivedData" >&2
              return 0
            fi

            BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist")
          xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
            open -a Simulator
            xcrun simctl terminate "$SIM_NAME" "$BUNDLE_ID" 2>/dev/null || true
            xcrun simctl install "$SIM_NAME" "$APP_PATH"
            xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID"
            echo "── ready, watching Goose/ for changes (Ctrl+C to stop) ──"
          }

          rebuild
          fswatch -o -l 0.5 --exclude '.*' --include '\.swift$' --include '\.xcassets' Goose | while read -r _; do
            rebuild
          done
        '';
      });
    };
}
