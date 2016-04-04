import parsemk.grammar;
import parsemk.reggae;
import std.stdio;
import std.file;


void main(string[] args) {
    auto parseTree = Makefile(cast(string)read(args[1]));
    //stderr.writeln(parseTree);
    writeln(toReggaeOutput(parseTree));
}
