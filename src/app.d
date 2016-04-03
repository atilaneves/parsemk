import parsemk.grammar;
import std.stdio;

enum input0 = `
# comments and stuff
#
QUIET:=foo
`;

enum input = `QUIET:=foo`;

void main() {
    auto parseTree = Makefile(input);
    writeln(parseTree);
}
