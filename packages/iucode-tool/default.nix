{ lib, stdenv, fetchzip }:

stdenv.mkDerivation rec {
  name = "iucode-tool-${version}";
  version = "2.3.1";
  src = fetchzip {
    url = "https://gitlab.com/iucode-tool/releases/raw/master/iucode-tool_${version}.tar.xz";
    sha256 = "0c3n2103hplvm6fp547fszvpgkb6zjg2dp69rflk52ffpppdp0wk";
  };
  meta = {
    description = "Manipulate Intel X86 and X86-64 processor microcode update collections";
    homepage = "https://gitlab.com/iucode-tool/";
    license = lib.licenses.gpl2;
  };
}
