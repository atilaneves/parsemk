import parsemk.grammar;
import parsemk.reggae;
import parsemk.io;
import std.stdio;
import std.file;
import std.array;



void main(string[] args) {
    auto input = cast(string)read(args[1]);
    auto parseTree = Makefile(input.sanitize);
    if(args.length > 2) stderr.writeln(parseTree);
    writeln(toReggaeOutputWithImport(parseTree));
}
