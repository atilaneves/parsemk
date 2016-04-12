import parsemk.grammar;
import parsemk.reggae;
import parsemk.io;
import std.stdio;
import std.file;
import std.array;



void main(string[] args) {
    const fileName = args[1];
    auto input = cast(string)read(fileName);
    auto parseTree = Makefile(input.sanitize);
    if(args.length > 2) stderr.writeln(parseTree);
    writeln(toReggaeOutputWithImport(fileName, parseTree));
}
