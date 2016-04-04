module parsemk.reggae;

import parsemk.grammar;
import pegged.grammar;
import std.array;
import std.exception;
import std.stdio;
import std.file;
import std.algorithm;
import std.regex;



version(unittest) import unit_threaded;
else {
    enum Serial;
}

struct Environment {
    bool[string] bindings;
}

string[] toReggaeLines(ParseTree parseTree) {
    auto environment = Environment();
    return toReggaeLines(parseTree, environment);
}

string[] toReggaeLines(ParseTree parseTree, ref Environment environment) {
    enforce(parseTree.name == "Makefile", "Unexpected parse tree " ~ parseTree.name);
    enforce(parseTree.children.length == 1);
    parseTree = parseTree.children[0];

    enforce(parseTree.name == "Makefile.Elements", "Unexpected parse tree " ~ parseTree.name);

    string[] elements;


    foreach(element; parseTree.children) {
        enforce(element.name == "Makefile.Element", "Unexpected parse tree " ~ element.name);
        elements ~= elementToReggae(element, environment);
    }

    return elements;
}


private string consultMakeVar(in string var) {
    return `makeVars["` ~ var ~ `"]`;
}

private string[] introduceNewBinding(ref Environment environment, in string var, in string val) {
    environment.bindings[var] = true;
    return [consultMakeVar(var) ~ ` = ` ~ val ~ `;`];
}

private string consultBinding(ref Environment environment, in string var, in string val) {
    return var in environment.bindings
                      ? consultMakeVar(var)
                      : `userVars.get("` ~ var ~ `", ` ~ val ~ `)`;
}

private string resolveVariablesInValue(in string val) {
    auto re = regex(`\$\((.+)\)`, "g");
    auto replacement = val.replaceAll(re, `" ~ makeVars["$1"] ~ "`);
    return `"` ~ replacement ~ `"`;

    // string ret = `"`;
    // auto varStart = val.countUntil("$(");

    // if(varStart == -1) return `"` ~ val ~ `"`;
    // while(varStart != -1) {
    //     varStart += 2; //skip $(
    //     ret ~= val[0 .. varStart - 2] ~ `" ~ `;
    //     val = val[varStart .. $];

    //     varStart = val.countUntil(")");
    //     ret ~= val[0 .. varStart];
    //     val = val[varStart + 1 .. $];

    //     varStart = val.countUntil("$(");
    //     val = val[0 .. $];
    // }

    // return ret ~ val;
}

private string[] assignmentToReggae(in ParseTree element, ref Environment environment, bool newBinding) {
    auto assignment = element.children[0];

    auto var   = assignment.matches[0];
    auto value = "";
    if(assignment.matches.length > 3) {
        value = assignment.matches[2 .. $-1].join;
    }
    value = resolveVariablesInValue(value);
    return newBinding
        ? introduceNewBinding(environment, var, value)
        : [consultMakeVar(var) ~ ` = userVars.get("` ~ var ~ `", ` ~ value ~ `);`];
}


string[] elementToReggae(in ParseTree element, ref Environment environment, bool topLevel = true) {
    switch(element.children[0].name) {
    case "Makefile.SimpleAssignment":
        auto newBinding = !topLevel;
        return assignmentToReggae(element, environment, newBinding);

    case "Makefile.RecursiveAssignment":
        auto newBinding = !topLevel;
        return assignmentToReggae(element, environment, newBinding);

    case "Makefile.Include":
        auto include = element.children[0];
        auto filenameNode = include.children[0];
        auto fileName = filenameNode.input[filenameNode.begin .. filenameNode.end];
        auto input = cast(string)read(fileName);
        return toReggaeLines(Makefile(input), environment);

    case "Makefile.Ignore":
        return [];

    case "Makefile.Line":
        return elementToReggae(element.children[0], environment, topLevel);

    case "Makefile.ConditionBlock":
        auto cond = element.children[0];
        auto varSigil = cond.matches.find(",$(");
        varSigil.popFront;
        auto var = varSigil.front;
        auto ifBlock = cond.children[0];
        auto ifElements = ifBlock.children;
        auto elseElements = cond.children.length > 2 ? cond.children[1].children : [];
        auto valueRange = cond.matches.find("(");
        valueRange.popFront;
        auto value = "";
        while(valueRange.front != ",$(") {
            value ~= valueRange.front;
            valueRange.popFront;
        }
        value = `"` ~ value ~ `"`;

        string[] flatMapToReggae(in ParseTree[] elements) {
            return elements.map!(a => elementToReggae(a, environment, false)).join.map!(a => "    " ~ a).array;
        }

        auto elseResult = flatMapToReggae(elseElements);
        return
            [`if(` ~ consultBinding(environment, var, value) ~ ` == ` ~ value ~ `) {`] ~
            flatMapToReggae(ifElements) ~
            (elseResult.length ? [`else {`] : []) ~
            elseResult ~
            `}`;

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ element.children[0].name);
    }
}

string toReggaeOutput(ParseTree parseTree) {
    return ([`import reggae;`] ~
            `string[string] makeVars; // dynamic variables` ~
            `auto _getBuild() {` ~
            toReggaeLines(parseTree).map!(a => "    " ~ a).array ~
            `}`).join("\n");
}


@("Variable assignment with := to auto QUIET") unittest {
    auto parseTree = Makefile("QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`auto QUIET = userVars.get("QUIET", "true");`]);
}

@("Variable assignment with := to auto FOO") unittest {
    auto parseTree = Makefile("FOO:=bar\n");
    toReggaeLines(parseTree).shouldEqual(
        [`auto FOO = userVars.get("FOO", "bar");`]);
}

@("Comments are ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`auto QUIET = userVars.get("QUIET", "true");`]);
}


@("Variables can be assigned to nothing") unittest {
    auto parseTree = Makefile("QUIET:=\n");
    toReggaeLines(parseTree).shouldEqual(
        [`auto QUIET = userVars.get("QUIET", "");`]);
}

@Serial
@("includes are expanded in place") unittest {
    auto fileName = "/tmp/inner.mk";
    {
        auto file = File(fileName, "w");
        file.writeln("OS:=solaris");
    }
    auto parseTree = Makefile("include " ~ fileName ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`auto OS = userVars.get("OS", "solaris");`]);
}

@("ifeq works correctly with no else block") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "OS=osx",
         "endif",
            ].join("\n") ~ "\n");

    toReggaeLines(parseTree).shouldEqual(
        [`if(userVars.get("OS", "") == "") {`,
         `    auto OS = "osx";`,
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
        [`if(userVars.get("OS", "MACOS") == "MACOS") {`,
         `    auto OS = "osx";`,
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
        [`if(userVars.get("BUILD", "") == "") {`,
         `    auto BUILD_WAS_SPECIFIED = "0";`,
         `    auto BUILD = "release";`,
         `else {`,
         `    auto BUILD_WAS_SPECIFIED = "1";`,
         `}`
        ]);
}

@Serial
@("includes with ifeq are expanded in place") unittest {
    auto fileName = "/tmp/inner.mk";
    {
        auto file = File(fileName, "w");
        file.writeln("ifeq (MACOS,$(OS))");
        file.writeln("  OS:=osx");
        file.writeln("endif");
    }
    auto parseTree = Makefile("include " ~ fileName ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if(userVars.get("OS", "MACOS") == "MACOS") {`,
         `    auto OS = "osx";`,
         `}`]);
}

@("nested ifeq") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "  uname_S:=Linux",
         "  ifeq (Darwin,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if(userVars.get("OS", "") == "") {`,
         `    auto uname_S = "Linux";`,
         `    if(uname_S == "Darwin") {`,
         `        auto OS = "osx";`,
         `    }`,
         `}`,
            ]);
}


@("Refer to declared variable") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(MODEL))",
         "  MODEL:=64",
         "endif",
         "MODEL_FLAG:=-m$(MODEL)",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if(userVars.get("MODEL", "") == "") {`,
         `    auto MODEL = "64";`,
         `}`,
         `auto MODEL_FLAG = userVars.get("MODEL_FLAG", "-m" ~ MODEL);`,
            ]);
}


// @("shell commands get translated to a module constructor") unittest {
//     auto parseTree = Makefile(
//         ["ifeq (,$(OS))",
//          "  uname_S:=$(shell uname -s)",
//          // "  ifeq (Linux, $(uname_S))",
//          // "    OS:=linux",
//          // "  endif",
//          "endif",
//         ].join("\n") ~ "\n";
//         );
//     toReggaeLines(parseTree).shouldEqual(
//         [`if(userVars.get("OS", "") == "") {`,
//          `    string uname_S;`,
//          `    static this() {`,
//          `        uname_S = executeShell("uname -s");`,
//          `    }`,
//          //`    if(uname_S)`
//          `}`,
//             ]);
// }
