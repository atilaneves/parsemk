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


string toReggaeOutput(ParseTree parseTree) {
    return q{
/**
 Automatically generated from parsing a Makefile, do not edit by hand
 */
import reggae;
import std.algorithm;
string[string] makeVars; // dynamic variables
string consultVar(in string var, in string default_ = "") {
    return var in makeVars ? makeVars[var] : userVars.get(var, default_);
}
// implementation of GNU make $(findstring)
string findstring(in string needle, in string haystack) {
    return haystack.canFind(needle) ? needle : "";
}
auto _getBuild() }
     ~ "{\n" ~
    (toReggaeLines(parseTree).map!(a => "    " ~ a).array ~ `}`).join("\n");
}

string[] toReggaeLinesOld(ParseTree parseTree) {
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

string[] toReggaeLines(ParseTree parseTree) {
    writeln(parseTree);
    enforce(parseTree.name == "Makefile", "Unexpected parse tree " ~ parseTree.name);
    enforce(parseTree.children.length == 1);
    parseTree = parseTree.children[0];

    enforce(parseTree.name == "Makefile.Statements", "Unexpected parse tree " ~ parseTree.name);

    string[] statements;

    foreach(statement; parseTree.children) {
        enforce(statement.name == "Makefile.Statement", "Unexpected parse tree " ~ statement.name);
        statements ~= statementToReggaeLines(statement, true);
    }

    return statements;
}


private string consultMakeVar(in string var) {
    return `makeVars["` ~ var ~ `"]`;
}


private string[] newMakeVar(in string var, in string val) {
    return [consultMakeVar(var) ~ ` = ` ~ val ~ `;`];
}

// resolve variables (e.g. $(FOO)) and make built-in functions such as $(shell)
private string resolveVariablesInValue(in string val) {
    string replacement = val;

    auto shellRe = regex(`\$\(shell (.+)\)`, "g");
    replacement = replacement.replaceAll(shellRe, `" ~ executeShell("$1").output ~ "`);

    auto varRe = regex(`\$\((.+)\)`, "g");
    replacement = replacement.replaceAll(varRe, `" ~ consultVar("$1") ~ "`);

    auto ret = `"` ~ replacement ~ `"`;
    ret = ret.replaceAll(regex(`^"" ~ `), "");
    ret = ret.replaceAll(regex(` ~ ""`), "");
    return ret;
}

// e.g. $(FOO) -> FOO
private string unsigil(in string var) {
    return var[2 .. $ - 1];
}

// At the top level, (file-scope), assignments need to consult
// the user-defined variables.
// At other levels, the assigment is done unconditionally
private string[] assignmentToReggae(in ParseTree element, bool topLevel) {
    auto assignment = element.children[0];

    auto var   = assignment.matches[0];
    auto value = "";
    if(assignment.matches.length > 3) { //non-empty value
        value = assignment.matches[2 .. $-1].join;
    }
    value = resolveVariablesInValue(value);
    return topLevel
        ? newMakeVar(var, `consultVar("` ~ var ~ `", ` ~ value ~ `)`)
        : newMakeVar(var, value);
}


string[] elementToReggae(in ParseTree element, bool topLevel = true) {
    switch(element.children[0].name) {
    case "Makefile.SimpleAssignment":
    case "Makefile.RecursiveAssignment":
        return assignmentToReggae(element, topLevel);

    case "Makefile.Include":
        auto include = element.children[0];
        auto filenameNode = include.children[0];
        auto fileName = filenameNode.input[filenameNode.begin .. filenameNode.end];
        auto input = cast(string)read(fileName);
        return toReggaeLinesOld(Makefile(input));

    case "Makefile.Empty":
        return [];

    case "Makefile.Comment":
        auto comment = element.children[0];
        return [`//` ~ comment.matches[1..$-1].join];

    case "Makefile.Line":
        return elementToReggae(element.children[0], topLevel);

    case "Makefile.Error":
        auto error = element.children[0];
        // slice: skip "$(error " and ")\n"
        return [`throw new Exception(` ~ resolveVariablesInValue(element.matches[1 .. $-2].join) ~ `);`];

    case "Makefile.Override":
        auto override_ = element.children[0];
        auto varDecl = override_.children[0];
        auto varVal  = override_.children[1];
        return [`makeVars["` ~ varDecl.matches.join ~ `"] = ` ~ elementToReggae(varVal, topLevel).join ~ `;`];

    case "Makefile.IfFunc":
        auto ifFunc = element.children[0];
        auto cond = ifFunc.children[0].matches.join;
        auto trueBranch = ifFunc.children[1].matches.join;
        auto fromTrueBranch = ifFunc.matches.join.find(trueBranch);
        auto elseBranch = fromTrueBranch.find(",")[1 .. $-1]; //skip "," and ")"
        return [resolveVariablesInValue(cond) ~ ` ? ` ~
                resolveVariablesInValue(trueBranch) ~ ` : ` ~
                resolveVariablesInValue(elseBranch)];

    case "Makefile.ConditionBlock":
        auto cond = element.children[0];
        auto ifBlock = cond.children[0];

        auto lhs = ifBlock.children[0].matches.join;
        auto rhs = ifBlock.children[1].matches.join;

        string findstringArg(in ParseTree arg) {
            return arg.children.any!(a => a.name == "Makefile.Variable")
                ? `consultVar("` ~ arg.matches.join.unsigil ~ `")`
                : `"` ~ arg.matches.join ~ `"`;
        }

        string findstring(in ParseTree findStr, string name) {
            auto needle = findStr.children[0];
            auto haystack = findStr.children[1];
            return `findstring(` ~ findstringArg(needle) ~ `, ` ~ findstringArg(haystack) ~ `)`;
        }

        string lookup(in ParseTree ifArg, string name) {
            if(!name.startsWith("$(")) return `"` ~ name ~ `"`;

            if(ifArg.children.any!(a => a.name == "Makefile.FindString")) {
                return findstring(ifArg.children[0], name);
            }

            name = unsigil(name);
            return `consultVar("` ~ name.replaceAll(regex(`\$\((.+)\)`), `$1`) ~ `", "")`;
        }

        lhs = lookup(ifBlock.children[0], lhs);
        rhs = lookup(ifBlock.children[1], rhs);

        // 2..$: skip the two sides (lhs, rhs) being compared
        auto ifElements = ifBlock.children[2..$];
        auto elseElements = cond.children.length > 2 ? cond.children[1].children : [];

        string[] flatMapToReggae(in ParseTree[] elements) {
            return elements.map!(a => elementToReggae(a, false)).join.map!(a => "    " ~ a).array;
        }

        auto operator = ifBlock.name == "Makefile.IfEqual" ? "==" : "!=";
        auto elseResult = flatMapToReggae(elseElements);
        return
            [`if(` ~ lhs ~ ` ` ~ operator ~ ` ` ~ rhs ~ `) {`] ~
            flatMapToReggae(ifElements) ~
            (elseResult.length ? [`} else {`] : []) ~
            elseResult ~
            `}`;

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ element.children[0].name);
    }
}


string[] statementToReggaeLines(in ParseTree statement, bool topLevel = true) {
    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.SimpleStatement":
    case "Makefile.CompoundStatement":
        return statementToReggaeLines(statement.children[0], topLevel);

    case "Makefile.ConditionBlock":
        auto ifBlock = statement.children[0];
        auto lhs = ifBlock.children[0];
        auto rhs = ifBlock.children[1];
        auto ifStatements = ifBlock.children[2..$];
        auto operator = `==`;
        string[] mapInnerStatements(in ParseTree[] statements) {
            return statements.map!(a => statementToReggaeLines(a, false)).join.map!(a => "    " ~ a).array;
        }
        auto elseStatements = statement.children.length > 1 ? statement.children[1].children : [];
        return [`if(` ~ eval(lhs) ~ ` ` ~ operator ~ ` ` ~ eval(rhs) ~ `) {`] ~
            mapInnerStatements(ifStatements) ~
            (elseStatements.length ? [`} else {`] : []) ~
            mapInnerStatements(elseStatements) ~
            `}`;

    case "Makefile.Assignment":
        // assignments at top-level need to consult userVars in order for
        // the values to be overridden at the command line.
        // assignments elsewhere unconditionally set the variable
        auto var = statement.children[0].matches.join;
        auto val = statement.children.length > 1 ? eval(statement.children[1]) : `""`;
        return topLevel
            ? [`makeVars["` ~ var ~ `"] = consultVar("` ~ var ~ `", ` ~ val ~ `);`]
            : [`makeVars["` ~ var ~ `"] = ` ~ val ~ `;`];

    case "Makefile.Include":
        auto fileNameTree = statement.children[0];
        auto fileName = fileNameTree.matches.join;
        auto input = cast(string)read(fileName);
        return toReggaeLines(Makefile(input));

    case "Makefile.Comment":
        // the slice gets rid of the "#" character
        return [`//` ~ statement.matches[1..$].join];

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ statement.name);
    }
}

string eval(in ParseTree expression) {
    switch(expression.name) {
    case "Makefile.Expression":
    case "Makefile.LiteralString":
        return expression.children.map!eval.join(` ~ `);
    case "Makefile.NonEmptyString":
    case "Makefile.EmptyString":
        return `"` ~ expression.matches.join ~ `"`;
    case "Makefile.Variable":
        return `consultVar("` ~ unsigil(expression.matches.join) ~ `", "")`;
    case "Makefile.Function":
        return eval(expression.children[0]);
    case "Makefile.Shell":
        return `executeShell(` ~ eval(expression.children[0]) ~ `).output`;
    default:
        throw new Exception("Unknown expression " ~ expression.name);
    }
}


@("Variable assignment with := to auto QUIET") unittest {
    auto parseTree = Makefile("QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["QUIET"] = consultVar("QUIET", "true");`]);
}

@("Variable assignment with := to auto FOO") unittest {
    auto parseTree = Makefile("FOO:=bar\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["FOO"] = consultVar("FOO", "bar");`]);
}

@("Comments are not ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "\n"
        "\n"
        "QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`// this is a comment`,
         `makeVars["QUIET"] = consultVar("QUIET", "true");`]);
}


@("Variables can be assigned to nothing") unittest {
    auto parseTree = Makefile("QUIET:=\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["QUIET"] = consultVar("QUIET", "");`]);
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
        [`makeVars["OS"] = consultVar("OS", "solaris");`]);
}

@("ifeq works correctly with literals and no else block") unittest {
    auto parseTree = Makefile(
        ["ifeq (,foo)",
         "OS=osx",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == "foo") {`,
         `    makeVars["OS"] = "osx";`,
         `}`
        ]);
}

@("ifeq works correctly with no else block") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "OS=osx",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == consultVar("OS", "")) {`,
         `    makeVars["OS"] = "osx";`,
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
        [`if("MACOS" == consultVar("OS", "")) {`,
         `    makeVars["OS"] = "osx";`,
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
        [`if("" == consultVar("BUILD", "")) {`,
         `    makeVars["BUILD_WAS_SPECIFIED"] = "0";`,
         `    makeVars["BUILD"] = "release";`,
         `} else {`,
         `    makeVars["BUILD_WAS_SPECIFIED"] = "1";`,
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
        [`if("MACOS" == consultVar("OS", "")) {`,
         `    makeVars["OS"] = "osx";`,
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
        [`if("" == consultVar("OS", "")) {`,
         `    makeVars["uname_S"] = "Linux";`,
         `    if("Darwin" == consultVar("uname_S", "")) {`,
         `        makeVars["OS"] = "osx";`,
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
        [`if("" == consultVar("MODEL", "")) {`,
         `    makeVars["MODEL"] = "64";`,
         `}`,
         `makeVars["MODEL_FLAG"] = consultVar("MODEL_FLAG", "-m" ~ consultVar("MODEL", ""));`,
            ]);
}


@("shell commands") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "  uname_S:=$(shell uname -s)",
         "  ifeq (Darwin,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == consultVar("OS", "")) {`,
         `    makeVars["uname_S"] = executeShell("uname -s").output;`,
         `    if("Darwin" == consultVar("uname_S", "")) {`,
         `        makeVars["OS"] = "osx";`,
         `    }`,
         `}`,
            ]);
}


// @("ifeq with space and variable on the left side") unittest {
//     auto parseTree = Makefile(
//         ["ifeq (MACOS,$(OS))",
//          "  OS:=osx",
//          "endif",
//          "ifeq (,$(MODEL))",
//          "  ifeq ($(OS), solaris)",
//          "    uname_M:=$(shell isainfo -n)",
//          "  endif",
//          "endif",
//         ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if("MACOS" == consultVar("OS", "")) {`,
//          `    makeVars["OS"] = "osx";`,
//          `}`,
//          `if("" == consultVar("MODEL", "")) {`,
//          `    if(consultVar("OS", "") == "solaris") {`,
//          `        makeVars["uname_M"] = executeShell("isainfo -n").output;`,
//          `    }`,
//          `}`,
//             ]);
// }

// @("error function") unittest {
//     auto parseTree = Makefile(
//         ["ifeq (,$(MODEL))",
//          "  $(error Model is not set for $(foo))",
//          "endif",
//             ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if("" == consultVar("MODEL", "")) {`,
//          `    throw new Exception("Model is not set for " ~ consultVar("foo"));`,
//          `}`,
//             ]);
// }


// @("ifneq") unittest {
//     auto parseTree = Makefile(
//         ["ifneq (,$(FOO))",
//          "  FOO_SET:=1",
//          "endif",
//             ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if("" != consultVar("FOO", "")) {`,
//          `    makeVars["FOO_SET"] = "1";`,
//          `}`,
//             ]);
// }

// @("ifneq findstring") unittest {
//     auto parseTree = Makefile(
//         ["uname_M:=x86_64",
//          "ifneq (,$(findstring $(uname_M),x86_64 amd64))",
//          "  MODEL:=64",
//          "endif",
//             ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["uname_M"] = consultVar("uname_M", "x86_64");`,
//          `if("" != findstring(consultVar("uname_M"), "x86_64 amd64")) {`,
//          `    makeVars["MODEL"] = "64";`,
//          `}`,
//             ]);
// }

// @("override with if") unittest {
//     auto parseTree = Makefile("override PIC:=$(if $(PIC),-fPIC,)\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["PIC"] = consultVar("PIC") ? "-fPIC" : "";`,
//             ]);

// }
