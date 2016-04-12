dub build
./parsemk src/phobos.mk > reggaefile.d
reggae -b binary -d DMD=dmd
./build
