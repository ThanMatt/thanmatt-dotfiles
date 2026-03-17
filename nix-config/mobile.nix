{ pkgs, ... }:

let
  # :: Compose the Android SDK with the components you actually need
  androidSdk = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ "34.0.0" "33.0.2" ];
    platformVersions   = [ "34" "33" ];
    abiVersions        = [ "x86_64" ];
    includeEmulator       = true;
    includeSystemImages   = true;
    systemImageTypes      = [ "google_apis_playstore" ];
    includeNDK            = false;
    includeExtras         = false;
  };
in
{
  # :: Mobile dev packages
  home.packages = with pkgs; [
    flutter
    androidSdk.androidsdk
    android-tools   # :: adb, fastboot
    jdk17
    gradle
  ];

  # :: Environment variables for Android/Flutter toolchain
  home.sessionVariables = {
    ANDROID_HOME    = "${androidSdk.androidsdk}/libexec/android-sdk";
    ANDROID_SDK_ROOT = "${androidSdk.androidsdk}/libexec/android-sdk";
    JAVA_HOME       = "${pkgs.jdk17}/lib/openjdk";
  };

  # :: Add Flutter and Android platform-tools to PATH
  home.sessionPath = [
    "${pkgs.flutter}/bin"
    "${androidSdk.androidsdk}/libexec/android-sdk/platform-tools"
    "${androidSdk.androidsdk}/libexec/android-sdk/cmdline-tools/latest/bin"
    "${androidSdk.androidsdk}/libexec/android-sdk/emulator"
  ];

  # :: Fish shell aliases and helpers for mobile dev
  programs.fish.shellAliases = {
    flutter-clean = "flutter clean && flutter pub get";
    apk-release   = "flutter build apk --release";
    apk-debug     = "flutter build apk --debug";
    emu-list      = "emulator -list-avds";
  };
}
