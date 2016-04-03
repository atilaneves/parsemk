module parsemk.reggae;

import parsemk.grammar;
import pegged.grammar;
import std.array;
import std.exception;
import std.stdio;
import std.file;


version(unittest) import unit_threaded;


string[] toReggaeLines(ParseTree parseTree) {
    enforce(parseTree.name == "Makefile", "Unexpected parse tree " ~ parseTree.name);
    enforce(parseTree.children.length == 1);
    parseTree = parseTree.children[0];

    enforce(parseTree.name == "Makefile.Lines", "Unexpected parse tree " ~ parseTree.name);

    string[] lines;


    foreach(line; parseTree.children) {
        enforce(line.name == "Makefile.Line", "Unexpected parse tree " ~ line.name);
        lines ~= lineToReggae(line);
    }

    return lines;
}

private string[] lineToReggae(in ParseTree line) {
    switch(line.children[0].name) {
    case "Makefile.Assignment":
        auto assignment = line.children[0];

        auto var   = assignment.matches[0];
        auto value = assignment.matches.length > 3 ? assignment.matches[2] : "";
        return ["enum " ~ var ~ ` = userVars.get("` ~ var ~ `", "` ~ value ~ `");`];

    case "Makefile.Include":
        auto include = line.children[0];
        auto filenameNode = include.children[0];
        auto fileName = filenameNode.input[filenameNode.begin .. filenameNode.end];
        auto input = cast(string)read(fileName);
        return toReggaeLines(Makefile(input));

    case "Makefile.Ignore":
        return [];

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ line.children[0].name);
    }
}

string toReggaeOutput(ParseTree parseTree) {
    return toReggaeLines(parseTree).join("\n");
}


@("Variable assignment with := to enum QUIET") unittest {
    auto parseTree = Makefile("QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = userVars.get("QUIET", "true");`]);
}

@("Variable assignment with := to enum FOO") unittest {
    auto parseTree = Makefile("FOO:=bar\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum FOO = userVars.get("FOO", "bar");`]);
}

@("Comments are ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = userVars.get("QUIET", "true");`]);
}


@("Variables can be assigned to nothing") unittest {
    auto parseTree = Makefile("QUIET:=\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum QUIET = userVars.get("QUIET", "");`]);
}


@("includes are expanded in place") unittest {
    enum fileName = "/tmp/inner.mk";
    {
        auto file = File(fileName, "w");
        file.writeln("OS:=solaris");
    }
    auto parseTree = Makefile("include " ~ fileName ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`enum OS = userVars.get("OS", "solaris");`]);
}
