import parsemk.grammar;
import parsemk.reggae;
import std.stdio;
import std.file;
import std.array;



void main(string[] args) {
    auto input = cast(string)read(args[1]);
    auto parseTree = Makefile(input.sanitize);
    stderr.writeln(parseTree);
    writeln(toReggaeOutputWithImport(parseTree));
}

string sanitize(in string input) {
    return input
        .replace("\\\n", "")
        .replace("$$", "$")
        ;
}
