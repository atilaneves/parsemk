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


string[] toReggaeLines(ParseTree parseTree) {
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

// e.g. $(FOO) -> FOO
private string unsigil(in string var) {
    return var[2 .. $ - 1];
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
        auto operator = ifBlock.name == "Makefile.IfEqual" ? "==" : "!=";
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
        return assignmentLines(statement, topLevel);

    case "Makefile.Override":
        return assignmentLines(statement, false);

    case "Makefile.Include":
        auto fileNameTree = statement.children[0];
        auto fileName = fileNameTree.matches.join;
        auto input = cast(string)read(fileName);
        return toReggaeLines(Makefile(input));

    case "Makefile.Comment":
        // the slice gets rid of the "#" character
        return [`//` ~ statement.matches[1..$].join];

    case "Makefile.Error":
        auto embedded = statement.children[0];
        // the slice gets rid of trailing ")"
        return [`throw new Exception(` ~ embedded.children[0 .. $-1].map!eval.join(` ~ `) ~ `);`];

    case "Makefile.Empty":
        return [];

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ statement.name);
    }
}

string[] assignmentLines(in ParseTree statement, in bool topLevel) {
    // assignments at top-level need to consult userVars in order for
    // the values to be overridden at the command line.
    // assignments elsewhere unconditionally set the variable
    auto var = statement.children[0].matches.join;
    auto val = statement.children.length > 1 ? eval(statement.children[1]) : `""`;
    return topLevel
        ? [`makeVars["` ~ var ~ `"] = consultVar("` ~ var ~ `", ` ~ val ~ `);`]
        : [`makeVars["` ~ var ~ `"] = ` ~ val ~ `;`];
}

string eval(in ParseTree expression) {
    switch(expression.name) {
    case "Makefile.Expression":
    case "Makefile.ArgExpression":
    case "Makefile.EmbeddedString":
        return expression.children.map!eval.join(` ~ `);
    case "Makefile.LiteralString":
    case "Makefile.ArgString":
    case "Makefile.NonEmptyString":
    case "Makefile.FreeFormString":
        return `"` ~ expression.matches.join ~ `"`;
    case "Makefile.Variable":
        return `consultVar("` ~ unsigil(expression.matches.join) ~ `", "")`;
    case "Makefile.Function":
    case "Makefile.FuncArg":
    case "Makefile.FuncLastArg":
        return expression.children.length ? eval(expression.children[0]) : `"` ~ expression.matches.join ~ `"`;
    case "Makefile.Shell":
        return `executeShell(` ~ eval(expression.children[0]) ~ `).output`;
    case "Makefile.FindString":
        return `findstring(` ~ eval(expression.children[0]) ~ `, ` ~ eval(expression.children[1]) ~ `)`;
    case "Makefile.IfFunc":
        auto cond = eval(expression.children[0]);
        auto trueBranch = eval(expression.children[1]);
        auto falseBranch = `""`;
        return cond ~ ` ? ` ~ trueBranch ~ ` : ` ~ falseBranch;

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


@("ifeq with space and variable on the left side") unittest {
    auto parseTree = Makefile(
        ["ifeq (MACOS,$(OS))",
         "  OS:=osx",
         "endif",
         "ifeq (,$(MODEL))",
         "  ifeq ($(OS), solaris)",
         "    uname_M:=$(shell isainfo -n)",
         "  endif",
         "endif",
        ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("MACOS" == consultVar("OS", "")) {`,
         `    makeVars["OS"] = "osx";`,
         `}`,
         `if("" == consultVar("MODEL", "")) {`,
         `    if(consultVar("OS", "") == "solaris") {`,
         `        makeVars["uname_M"] = executeShell("isainfo -n").output;`,
         `    }`,
         `}`,
            ]);
}

@("error statement 1") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(MODEL))",
         "  $(error Model is not set for $(foo))",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == consultVar("MODEL", "")) {`,
         `    throw new Exception("Model is not set for " ~ consultVar("foo", ""));`,
         `}`,
            ]);
}

@("error statement 2") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "  $(error Unrecognized or unsupported OS for uname: $(uname_S))",
         "endif",
         ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == consultVar("OS", "")) {`,
         `    throw new Exception("Unrecognized or unsupported OS for uname: " ~ consultVar("uname_S", ""));`,
         `}`,
            ]);
}


@("ifneq") unittest {
    auto parseTree = Makefile(
        ["ifneq (,$(FOO))",
         "  FOO_SET:=1",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" != consultVar("FOO", "")) {`,
         `    makeVars["FOO_SET"] = "1";`,
         `}`,
            ]);
}

@("ifneq findstring") unittest {
    auto parseTree = Makefile(
        ["uname_M:=x86_64",
         "ifneq (,$(findstring $(uname_M),x86_64 amd64))",
         "  MODEL:=64",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["uname_M"] = consultVar("uname_M", "x86_64");`,
         `if("" != findstring(consultVar("uname_M", ""), "x86_64 amd64")) {`,
         `    makeVars["MODEL"] = "64";`,
         `}`,
            ]);
}

@("override with if") unittest {
    auto parseTree = Makefile("override PIC:=$(if $(PIC),-fPIC,)\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["PIC"] = consultVar("PIC", "") ? "-fPIC" : "";`,
            ]);
}
