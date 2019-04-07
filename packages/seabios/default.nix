{ stdenv, fetchurl, iasl, python27 }:

stdenv.mkDerivation rec {
  name = "seabios-${version}";
  version = "1.11.0";

  src = fetchurl {
    url = "http://code.coreboot.org/p/seabios/downloads/get/${name}.tar.gz";
    sha256 = "1xwvp77djxbxbxg82hzj26pv6zka3556vkdcp09hnfwapcp46av2";
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ python27 iasl ];

  hardeningDisable = [ "pic" "stackprotector" "fortify" ];

  outputs = [ "out" "config" ];

  # Configs are documented at https://github.com/coreboot/seabios/blob/master/src/Kconfig
  configurePhase = ''
    cat >.config << EOF
    CONFIG_QEMU=y

    CONFIG_RELOCATE_INIT=n
    CONFIG_USE_SMM=n
    CONFIG_WRITABLE_UPPERMEMORY=y

    CONFIG_BOOTMENU=n
    CONFIG_BOOTORDER=n
    CONFIG_BOOTSPLASH=n
    CONFIG_KEYBOARD=n
    CONFIG_MOUSE=n

    CONFIG_LPT=n
    CONFIG_SERIAL=n
    CONFIG_TCGBIOS=n
    CONFIG_USB=n
    CONFIG_VGAHOOKS=n
    CONFIG_DRIVES=n

    CONFIG_DEBUG=0
    EOF
    make olddefconfig
  '';

  installPhase = ''
    install -Dt $config .config   -m 444
    install -Dt $out out/bios.bin -m 444
  '';

  meta = with stdenv.lib; {
    description = "Open source implementation of a 16bit X86 BIOS";
    longDescription = ''
      SeaBIOS is an open source implementation of a 16bit X86 BIOS.
      It can run in an emulator or it can run natively on X86 hardware with the use of coreboot.
      SeaBIOS is the default BIOS for QEMU and KVM.
    '';
    homepage = http://www.seabios.org;
    license = licenses.lgpl3;
    platforms = [ "x86_64-linux" ];
  };
}
