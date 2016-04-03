module parsemk.reggae;

import parsemk.grammar;
import pegged.grammar;
import std.array;
import std.exception;
import std.stdio;


version(unittest) import unit_threaded;


string[] toReggaeLines(ParseTree parseTree) pure {
    enforce(parseTree.name == "Makefile", "Unexpected parse tree " ~ parseTree.name);
    enforce(parseTree.children.length == 1);
    parseTree = parseTree.children[0];

    enforce(parseTree.name == "Makefile.Lines", "Unexpected parse tree " ~ parseTree.name);

    string[] lines;


    foreach(line; parseTree.children) {
        enforce(line.name == "Makefile.Line", "Unexpected parse tree " ~ line.name);
        if(line.children[0].name == "Makefile.Assignment") {
            auto assignment = line.children[0];

            auto var   = assignment.matches[0];
            auto value = assignment.matches.length > 3 ? assignment.matches[2] : "";
            lines ~= "enum " ~ var ~ " = " ~ `"` ~ value ~ `";`;
        }
    }

    return lines;
}

string toReggaeOutput(ParseTree parseTree) pure {
    return toReggaeLines(parseTree).join("\n");
}


@("Variable assignment with := to enum QUIET") unittest {
    auto parseTree = Makefile("QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = "true";`]);
}

@("Variable assignment with := to enum FOO") unittest {
    auto parseTree = Makefile("FOO:=bar\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum FOO = "bar";`]);
}

@("Comments are ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = "true";`]);
}


@("Variables can be assigned to nothing") unittest {
    auto parseTree = Makefile("QUIET:=\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = "";`]);
}
