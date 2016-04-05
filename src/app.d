import parsemk.grammar;
import parsemk.reggae;
import std.stdio;
import std.file;
import std.array;



void main(string[] args) {
    auto input = cast(string)read(args[1]);
    input = input.replace("\\\n", "");
    auto parseTree = Makefile(input);
    //stderr.writeln(parseTree);
    writeln(toReggaeOutput(parseTree));
}
