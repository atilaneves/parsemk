module parsemk.reggae;

import parsemk.grammar;
import pegged.grammar;
import std.array;
import std.exception;


version(unittest) import unit_threaded;


string[] toReggaeLines(ParseTree parseTree) pure {
    enforce(parseTree.name == "Makefile", "Unexpected parse tree " ~ parseTree.name);
    enforce(parseTree.children.length == 1);
    parseTree = parseTree.children[0];

    enforce(parseTree.name == "Makefile.Lines", "Unexpected parse tree " ~ parseTree.name);

    string[] lines;


    foreach(line; parseTree.children) {
        enforce(line.name == "Makefile.Line", "Unexpected parse tree " ~ line.name);
        auto assignment = line.children[0];

        lines ~= "enum " ~
            assignment.matches[0] ~
            " = " ~
            `"` ~ assignment.matches[2] ~ `";`;
    }

    return lines;
}

string toReggaeOuput(ParseTree parseTree) pure {
    return toReggaeLines(parseTree).join("\n");
}


@("Variable assignment with := to enum QUIET") unittest {
    auto parseTree = Makefile(`QUIET:=true`);
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = "true";`]);
}

@("Variable assignment with := to enum FOO") unittest {
    auto parseTree = Makefile(`FOO:=bar`);
    toReggaeLines(parseTree).shouldEqual(
        [`enum FOO = "bar";`]);
}
