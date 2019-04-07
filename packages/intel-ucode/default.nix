{ lib, stdenv, fetchurl, iucode-tool }:

stdenv.mkDerivation rec {
  name = "microcode-intel-${version}";

  # http://www.intel.com/content/www/us/en/search.html?keyword=Processor+Microcode+Data+File
  version = "20180807a";
  dlid = "28087";

  src = fetchurl {
    url = "https://downloadmirror.intel.com/${dlid}/eng/microcode-${version}.tgz";
    sha256 = "0dw1akgzdqk95pwmc8gfdmv7kabw9pn4c67f076bcbn4krliias6";
  };

  nativeBuildInputs = [ iucode-tool ];

  sourceRoot = ".";

  buildPhase = ''
    iucode_tool \
      --strict-checks \
      --no-ignore-broken \
      --list-all \
      --list \
      --mini-earlyfw \
      --write-earlyfw=intel-ucode.img \
      intel-ucode
  '';

  installPhase = ''
    install -m 444 -Dt $out intel-ucode.img
  '';

  meta = with lib; {
    description = "Microcode for Intel processors";
    longDescription = ''
      An early (uncompressed) initramfs containing microcode updates for
      Intel processors.
    '';
    homepage = "http://www.intel.com/";
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux;
  };
}
