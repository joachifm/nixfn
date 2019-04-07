{ lib, stdenv, fetchzip, python27, iasl, nasm, libuuid }:

with lib;

let
  supportedArch = {
    "x86_64-linux" = "X64";
    "i686-linux" = "IA32";
  };

  targetArch = supportedArch.${stdenv.system}
    or (throw "unsupported system: ${stdenv.system}");

  targetTools = "GCC5";
in

stdenv.mkDerivation rec {
  name = "edk2-ovmf-${version}";
  version = "2018";

  src = fetchzip {
    url = "https://github.com/tianocore/edk2/archive/vUDK${version}.tar.gz";
    sha256 = "0ll4xik9xw5spzcwnm5h34i8y6yag1nng8j55ji8jqiwrf94x23f";
  };

  enableParallelBuilding = true;

  hardeningDisable = [ "all" ];

  nativeBuildInputs = [ python27 iasl nasm ];

  buildInputs = [ libuuid ];

  buildPhase = ''
    set -a
    GCC5_IA32_PREFIX=""
    GCC5_X64_PREFIX=""
    IASL_PREFIX=""
    set +a

    make ARCH=${targetArch} -C BaseTools -j1
    . edksetup.sh
    $shell OvmfPkg/build.sh \
      -a ${targetArch} \
      -t ${targetTools} \
      -b RELEASE \
      -D FD_SIZE_2MB \
      -n ''${NIX_BUILD_CORES:-1}
  '';

  installPhase = ''
    install -m 444 -Dt $out/share/ovmf Build/Ovmf${targetArch}/RELEASE_${targetTools}/FV/OVMF_{CODE,VARS}.fd
  '';

  passthru = {
    OVMF_CODE = "/share/OVMF_CODE.fd";
    OVMF_VARS = "/share/OVMF_VARS.fd";
    inherit targetArch;
  };

  meta = {
    description = "UEFI firmware for x64 virtual machines";
    homepage = "http://www.tianocore.org/edk2/";
    license = licenses.bsd2;
    platforms = attrNames supportedArch;
  };
}
