dub build
./parsemk src/phobos.mk > reggaefile.d
#dub run reggae -- -b binary
reggae -b binary
#dmd -I~/.dub/packages/reggae-master/payload -c reggaefile.d
./build
