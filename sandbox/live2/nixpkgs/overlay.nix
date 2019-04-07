self: super:

{
  glibcLocalesMinimal = super.glibcLocales.override {
    locales = [ "en_US.UTF-8/UTF-8" ];
    allLocales = false;
  };
}
