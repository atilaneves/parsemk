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


string toReggaeOutputWithImport(ParseTree parseTree) {
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

string toReggaeOutput(ParseTree parseTree) {
    return q{
/**
 Automatically generated from parsing a Makefile, do not edit by hand
 */
import std.algorithm;
string[string] makeVars; // dynamic variables
string consultVar(in string var, in string default_ = "") {
    return var in makeVars ? makeVars[var] : userVars.get(var, default_);
}
// implementation of GNU make $(findstring)
string findstring(in string needle, in string haystack) {
    return haystack.canFind(needle) ? needle : "";
}
int _getBuild() }
     ~ "{\n" ~
    (toReggaeLines(parseTree).map!(a => "    " ~ a).array ~
     "    return 5;\n"
     `}`).join("\n") ~ "\n";

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

    case "Makefile.PlusEqual":
        auto var = statement.children[0].matches.join;
        auto val = eval(statement.children[1]);
        return [makeVar(var) ~ ` = ` ~ consultVar(var) ~ ` ~ ` ~ val ~ `;`];

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
        ? [makeVar(var) ~ ` = "` ~ var ~ `" in userVars ? userVars["` ~ var ~ `"]` ~ ` : ` ~ val ~ `;`]
        : [makeVar(var) ~ ` = ` ~ val ~ `;`];
}

private string makeVar(in string varName) {
    return `makeVars["` ~ varName ~ `"]`;
}

private string consultVar(in string varName) {
    return `consultVar("` ~ varName ~ `")`;
}

private string consultVar(in string varName, in string default_) {
    return `consultVar("` ~ varName ~ `", ` ~ default_ ~ `)`;
}


string eval(in ParseTree expression) {
    switch(expression.name) {
    case "Makefile.Expression":
    case "Makefile.EmbeddedString":
    case "Makefile.SpaceArgExpression":
        return expression.children.map!eval.join(` ~ `);
    case "Makefile.LiteralString":
    case "Makefile.ArgString":
    case "Makefile.NonEmptyString":
    case "Makefile.FreeFormString":
    case "Makefile.SpaceArgString":
        return evalLiteralString(expression.matches.join);
    case "Makefile.Variable":
        return `consultVar("` ~ unsigil(expression.matches.join) ~ `", "")`;
    case "Makefile.Function":
    case "Makefile.FuncArg":
    case "Makefile.FuncLastArg":
        return expression.children.length ? eval(expression.children[0]) : evalLiteralString(expression.matches.join);
    case "Makefile.Shell":
        return `executeShell(` ~ eval(expression.children[0]) ~ `).output`;
    case "Makefile.FindString":
        return `findstring(` ~ eval(expression.children[0]) ~ `, ` ~ eval(expression.children[1]) ~ `)`;
    case "Makefile.IfFunc":
        auto cond = eval(expression.children[0]);
        auto trueBranch = eval(expression.children[1]);
        auto falseBranch = `""`;
        return cond ~ ` ? ` ~ trueBranch ~ ` : ` ~ falseBranch;
    case "Makefile.Subst":
        auto from = expression.children[0];
        auto to = expression.children[1];
        auto text = expression.children[2];
        return eval(text) ~ `.replace(` ~ eval(from) ~ `, ` ~ eval(to) ~ `)`;

    case "Makefile.AddPrefix":
        auto prefix = expression.children[0];
        auto names = expression.children[1..$];
        return `[` ~ names.map!eval.join(", ") ~ `].map!(a => ` ~ eval(prefix) ~ ` ~ a).array`;

    case "Makefile.AddSuffix":
        auto suffix = expression.children[0];
        auto names = expression.children[1..$];
        return `[` ~ names.map!eval.join(", ") ~ `].map!(a => a ~ ` ~ eval(suffix) ~ `).array`;


    default:
        throw new Exception("Unknown expression " ~ expression.name);
    }
}

string evalLiteralString(in string str) {
    auto repl = str
        .replace(`\`, `\\`)
        .replace(`"`, `\"`)
        ;

    return `"` ~ repl ~ `"`;
}

version(unittest) {

    mixin template TestMakeToReggaeUserVars(string[string] _userVars, string[] lines) {
        string[string] userVars = _userVars;
        mixin TestMakeToReggaeNoUserVars!lines;
    }

    mixin template TestMakeToReggae(string[] lines) {
        string[string] userVars;
        mixin TestMakeToReggaeNoUserVars!lines;
    }

    mixin template TestMakeToReggaeNoUserVars(string[] lines) {

        enum parseTree = Makefile(lines.map!(a => a ~ "\n").join);
        enum code = toReggaeOutput(parseTree);
        mixin(code);

        string access(string var)() {
            return makeVars[var];
        }

        auto build = _getBuild();

        void makeVarShouldBe(string varName)(string value,
                                             string file = __FILE__, size_t line = __LINE__) {
            try {
                makeVars[varName].shouldEqual(value, file, line);
            } catch(Throwable t) {
                writeln(parseTree);
                writeln("----------------------------------------\n",
                        code,
                        "----------------------------------------\n");
                throw t;
            }
        }

        void makeVarShouldNotBeSet(string varName)(string file = __FILE__, size_t line = __LINE__) {
            varName.shouldNotBeIn(makeVars);
        }
    }
}

@("Top-level assignment to QUIET with no customization") unittest {
    mixin TestMakeToReggae!(["QUIET:=true"]);
    makeVarShouldBe!"QUIET"("true");
}

@("Top-level assignment to FOO with no customization") unittest {
    mixin TestMakeToReggae!(["FOO:=bar"]);
    makeVarShouldBe!"FOO"("bar");
}

@("Top-level assignment to QUIET with customization") unittest {
    mixin TestMakeToReggaeUserVars!(["QUIET": "foo"], ["QUIET:=true"]);
    makeVarShouldBe!"QUIET"("foo");
}


@("Comments are not ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "\n"
        "\n"
        "QUIET:=true\n");
    "// this is a comment".shouldBeIn(toReggaeLines(parseTree));
}


@("Top-level assignment to nothing") unittest {
    mixin TestMakeToReggae!(["QUIET:="]);
    makeVarShouldBe!"QUIET"("");
}

//this file can't mixin and use the code since
//it depends on runtime (reading the file)
//it's only one line so easy to change when/if
//the implementation changes
@Serial
@("includes are expanded in place") unittest {
    auto fileName = "/tmp/inner.mk";
    {
        auto file = File(fileName, "w");
        file.writeln("OS:=solaris");
    }
    auto parseTree = Makefile("include " ~ fileName ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["OS"] = "OS" in userVars ? userVars["OS"] : "solaris";`]);
}

@("ifeq with literals and no else block") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,foo)",
         "OS=osx",
         "endif"
            ]);
    makeVarShouldNotBeSet!"OS";
}

@("ifeq with rhs variable, no else block and no user vars") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,$(OS))",
         "OS=osx",
         "endif",
            ]);
    makeVarShouldBe!"OS"("osx");
}

@("ifeq with rhs variable, no else block and user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["OS": "Windows"],
        ["ifeq (,$(OS))",
         "OS=osx",
         "endif",
            ]);
    makeVarShouldNotBeSet!"OS";
}

@("ifeq with non-empty comparison, no else block and no user vars") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (MACOS,$(OS))",
         "OS=osx",
         "endif",
            ]);
    makeVarShouldNotBeSet!"OS";
}

@("ifeq with non-empty comparison, no else block and user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["OS": "MACOS"],
        ["ifeq (MACOS,$(OS))",
         "OS=osx",
         "endif",
            ]);
    makeVarShouldBe!"OS"("osx");
}


@("ifeq works with else block and no user vars") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,$(BUILD))",
         "BUILD_WAS_SPECIFIED=0",
         "BUILD=release",
         "else",
         "BUILD_WAS_SPECIFIED=1",
         "endif",
            ]);
    makeVarShouldBe!"BUILD_WAS_SPECIFIED"("0");
    makeVarShouldBe!"BUILD"("release");
}

@("ifeq works with else block and user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["BUILD": "debug"],
        ["ifeq (,$(BUILD))",
         "BUILD_WAS_SPECIFIED=0",
         "BUILD=release",
         "else",
         "BUILD_WAS_SPECIFIED=1",
         "endif",
            ]);

    makeVarShouldBe!"BUILD_WAS_SPECIFIED"("1");
    makeVarShouldNotBeSet!"BUILD";
}

@("nested ifeq with no user vars") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,$(OS))",
         "  uname_S:=Linux",
         "  ifeq (Darwin,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ]);
    makeVarShouldBe!"uname_S"("Linux");
    makeVarShouldNotBeSet!"OS";
}

@("nested ifeq with OS user var") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["OS": "Linux"],
        ["ifeq (,$(OS))",
         "  uname_S:=Linux",
         "  ifeq (Darwin,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ]);
    makeVarShouldNotBeSet!"uname_S";
    makeVarShouldNotBeSet!"OS";
}


@("Assignment to variabled embedded in string with no user vars") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,$(MODEL))",
         "  MODEL:=64",
         "endif",
         "MODEL_FLAG:=-m$(MODEL)",
            ]);
    makeVarShouldBe!"MODEL_FLAG"("-m64");
}

@("Assignment to variabled embedded in string with user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["MODEL": "32"],
        ["ifeq (,$(MODEL))",
         "  MODEL:=64",
         "endif",
         "MODEL_FLAG:=-m$(MODEL)",
            ]);
    makeVarShouldBe!"MODEL_FLAG"("-m32");
}


// @("shell commands") unittest {
//     auto parseTree = Makefile(
//         ["ifeq (,$(OS))",
//          "  uname_S:=$(shell uname -s)",
//          "  ifeq (Darwin,$(uname_S))",
//          "    OS:=osx",
//          "  endif",
//          "endif",
//             ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if("" == consultVar("OS", "")) {`,
//          `    makeVars["uname_S"] = executeShell("uname -s").output;`,
//          `    if("Darwin" == consultVar("uname_S", "")) {`,
//          `        makeVars["OS"] = "osx";`,
//          `    }`,
//          `}`,
//             ]);
// }


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

// @("error statement 1") unittest {
//     auto parseTree = Makefile(
//         ["ifeq (,$(MODEL))",
//          "  $(error Model is not set for $(foo))",
//          "endif",
//             ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if("" == consultVar("MODEL", "")) {`,
//          `    throw new Exception("Model is not set for " ~ consultVar("foo", ""));`,
//          `}`,
//             ]);
// }

// @("error statement 2") unittest {
//     auto parseTree = Makefile(
//         ["ifeq (,$(OS))",
//          "  $(error Unrecognized or unsupported OS for uname: $(uname_S))",
//          "endif",
//          ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if("" == consultVar("OS", "")) {`,
//          `    throw new Exception("Unrecognized or unsupported OS for uname: " ~ consultVar("uname_S", ""));`,
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
//          `if("" != findstring(consultVar("uname_M", ""), "x86_64 amd64")) {`,
//          `    makeVars["MODEL"] = "64";`,
//          `}`,
//             ]);
// }

// @("override with if") unittest {
//     auto parseTree = Makefile("override PIC:=$(if $(PIC),-fPIC,)\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["PIC"] = consultVar("PIC", "") ? "-fPIC" : "";`,
//             ]);
// }

// @("+=") unittest {
//     auto parseTree = Makefile(
//         ["ifeq ($(BUILD),debug)",
//          "  CFLAGS += -g",
//          "endif",
//             ].join("\n") ~ "\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`if(consultVar("BUILD", "") == "debug") {`,
//          `    makeVars["CFLAGS"] = consultVar("CFLAGS") ~ "-g";`,
//          `}`,
//             ]);
// }

// @("shell in assigment") unittest {
//     auto parseTree = Makefile(`PATHSEP:=$(shell echo "\\")` ~ "\n");
//     writeln(parseTree);
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["PATHSEP"] = consultVar("PATHSEP", executeShell("echo \"\\\\\"").output);`,
//             ]);
// }


// @("subst") unittest {
//     auto parseTree = Makefile("P2LIB=$(subst /,_,$1)\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["P2LIB"] = consultVar("P2LIB", "$1".replace("/", "_"));`,
//             ]);
// }

// @("addprefix") unittest {
//     auto parseTree = Makefile("FOO=$(addprefix std/,algorithm container)\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["FOO"] = consultVar("FOO", ["algorithm", "container"].map!(a => "std/" ~ a).array);`,
//             ]);
// }

// @("addsuffix") unittest {
//     auto parseTree = Makefile("FOO=$(addsuffix .c,foo bar)\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["FOO"] = consultVar("FOO", ["foo", "bar"].map!(a => a ~ ".c").array);`,
//             ]);
// }

// @("addsuffix subst") unittest {
//     auto parseTree = Makefile("FOO=$(addsuffix $(DOTLIB),$(subst /,_,$1))\n");
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["FOO"] = consultVar("FOO", ["$1".replace("/", "_")].map!(a => a ~ consultVar("DOTLIB", "")).array);`,
//             ]);

// }

// @("addprefix addsuffix subst") unittest {
//     //auto parseTree = Makefile("P2LIB=$(addprefix $(ROOT)/libphobos2_,$(addsuffix $(DOTLIB),$(subst /,_,$1)))\n");
//     auto parseTree = Makefile("P2LIB=$(addprefix $(ROOT),$(addsuffix $(DOTLIB),$(subst /,_,$1)))\n");
//     writeln(parseTree);
//     toReggaeLines(parseTree).shouldEqual(
//         [`makeVars["P2LIB"] = consultVar("P2LIB", [["$1".replace("/", "_")].map!(a => a ~ consultVar("DOTLIB", "")).array].map!(a => consultVar("ROOT", "") ~ a).array);`,
//             ]);

// }
