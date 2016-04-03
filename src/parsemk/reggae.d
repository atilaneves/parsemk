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

    enforce(parseTree.name == "Makefile.Elements", "Unexpected parse tree " ~ parseTree.name);

    string[] elements;


    foreach(element; parseTree.children) {
        enforce(element.name == "Makefile.Element", "Unexpected parse tree " ~ element.name);
        elements ~= elementToReggae(element);
    }

    return elements;
}

string[] elementToReggae(in ParseTree element) {
    switch(element.children[0].name) {
    case "Makefile.SimpleAssignment":
        auto assignment = element.children[0];

        auto var   = assignment.matches[0];
        auto value = "";
        if(assignment.matches.length > 3) {
            value = assignment.matches[2 .. $-1].join;
        }
        return ["enum " ~ var ~ ` = userVars.get("` ~ var ~ `", "` ~ value ~ `");`];

    case "Makefile.RecursiveAssignment":
        auto assignment = element.children[0];

        auto var   = assignment.matches[0];
        auto value = "";
        if(assignment.matches.length > 3) {
            value = assignment.matches[2 .. $-1].join;
        }
        return ["enum " ~ var ~ ` = "` ~ value ~ `";`];


    case "Makefile.Include":
        auto include = element.children[0];
        auto filenameNode = include.children[0];
        auto fileName = filenameNode.input[filenameNode.begin .. filenameNode.end];
        auto input = cast(string)read(fileName);
        return toReggaeLines(Makefile(input));

    case "Makefile.Ignore":
        return [];

    case "Makefile.Line":
        return elementToReggae(element.children[0]);

    case "Makefile.ConditionBlock":

        auto cond = element.children[0];
        auto var = cond.matches[3];
        auto ifBlock = cond.children[0];
        auto lines = ifBlock.children;
        auto elseLines = cond.children.length > 2 ? cond.children[1].children : [];
        auto value = `""`;

        string[] flatMapToReggae(in ParseTree[] lines) {
            return lines.map!(elementToReggae).join.map!(a => "    " ~ a).array;
        }

        auto elseResult = flatMapToReggae(elseLines);
        return [`static if(userVars.get("` ~ var ~ `", ` ~ value ~ `) == ` ~ value ~ `) {`] ~
            flatMapToReggae(lines) ~
            (elseResult.length ? `else {` : []) ~
            elseResult ~
            `}`;

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ element.children[0].name);
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


@("ifeq works correctly") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(BUILD)",
         "BUILD_WAS_SPECIFIED=0",
         "BUILD=release",
         "else",
         "BUILD_WAS_SPECIFIED=1",
         "endif",
            ].join("\n") ~ "\n");

    toReggaeLines(parseTree).shouldEqual(
        [`static if(userVars.get("BUILD", "") == "") {`,
         `    enum BUILD_WAS_SPECIFIED = "0";`,
         `    enum BUILD = "release";`,
         `else {`,
         `    enum BUILD_WAS_SPECIFIED = "1";`,
         `}`
        ]);
}
