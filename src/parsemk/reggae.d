module parsemk.reggae;

import parsemk.grammar;
import pegged.grammar;
import std.array;
import std.exception;
import std.stdio;
import std.file;
import std.algorithm;



version(unittest) import unit_threaded;
else {
    enum Serial;
}


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

string[] elementToReggae(in ParseTree element, bool topLevel = true) {
    switch(element.children[0].name) {
    case "Makefile.SimpleAssignment":
        auto assignment = element.children[0];

        auto var   = assignment.matches[0];
        auto value = "";
        if(assignment.matches.length > 3) {
            value = assignment.matches[2 .. $-1].join;
        }
        return topLevel
            ? ["enum " ~ var ~ ` = userVars.get("` ~ var ~ `", "` ~ value ~ `");`]
            : ["enum " ~ var ~ ` = "` ~ value ~ `";`];

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
        auto varSigil = cond.matches.find(",$(");
        varSigil.popFront;
        auto var = varSigil.front;
        auto ifBlock = cond.children[0];
        auto lines = ifBlock.children;
        auto elseLines = cond.children.length > 2 ? cond.children[1].children : [];
        auto valueRange = cond.matches.find("(");
        valueRange.popFront;
        auto value = "";
        while(valueRange.front != ",$(") {
            value ~= valueRange.front;
            valueRange.popFront;
        }
        value = `"` ~ value ~ `"`;

        string[] flatMapToReggae(in ParseTree[] lines) {
            return lines.map!(a => elementToReggae(a, false)).join.map!(a => "    " ~ a).array;
        }

        auto elseResult = flatMapToReggae(elseLines);
        return [`static if(userVars.get("` ~ var ~ `", ` ~ value ~ `) == ` ~ value ~ `) {`] ~
            flatMapToReggae(lines) ~
            (elseResult.length ? [`else {`] : []) ~
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

@Serial
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

@("ifeq works correctly with no else block") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "OS=osx",
         "endif",
            ].join("\n") ~ "\n");

    toReggaeLines(parseTree).shouldEqual(
        [`static if(userVars.get("OS", "") == "") {`,
         `    enum OS = "osx";`,
         `}`
        ]);
}

@("ifeq works correctly with no else block and non-empty comparison") unittest {
    auto parseTree = Makefile(
        ["ifeq (MACOS,$(OS))",
         "OS=osx",
         "endif",
            ].join("\n") ~ "\n");

    toReggaeLines(parseTree).shouldEqual(
        [`static if(userVars.get("OS", "MACOS") == "MACOS") {`,
         `    enum OS = "osx";`,
         `}`
        ]);
}


@("ifeq works correctly with else block") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(BUILD))",
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

@Serial
@("includes with ifeq are expanded in place") unittest {
    enum fileName = "/tmp/inner.mk";
    {
        auto file = File(fileName, "w");
        file.writeln("ifeq (MACOS,$(OS))");
        file.writeln("  OS:=osx");
        file.writeln("endif");
    }
    auto parseTree = Makefile("include " ~ fileName ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`static if(userVars.get("OS", "MACOS") == "MACOS") {`,
         `    enum OS = "osx";`,
         `}`]);
}
