import grammar;
import std.stdio;

enum input = `
# comments and stuff
#
QUIET:=foo
`;

void main() {
    auto parseTree = Makefile(input);
    writeln(parseTree);
}
