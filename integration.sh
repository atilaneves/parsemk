dub build
./parsemk src/phobos.mk > reggaefile.d
dub run reggae -- -b binary
./build
