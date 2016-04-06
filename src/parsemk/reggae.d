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
    enum ShouldFail;
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
import std.process;
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
        // one of the sides could be empty
        auto numExpressions = ifBlock.children.count!(a => a.name == "Makefile.Expression");
        auto lhs = ifBlock.children[0];
        auto rhs = numExpressions > 1 ? ifBlock.children[1] : ParseTree("Makefile.EmptyString");
        auto firstStatementIndex = ifBlock.children.countUntil!(a => a.name == "Makefile.Statement");
        auto ifStatements = ifBlock.children[firstStatementIndex .. $];
        auto operator = ifBlock.name == "Makefile.IfEqual" ? "==" : "!=";
        string[] mapInnerStatements(in ParseTree[] statements) {
            return statements.map!(a => statementToReggaeLines(a, false)).join.map!(a => "    " ~ a).array;
        }
        auto elseStatements = statement.children.length > 1 ? statement.children[1].children : [];
        return [`if(` ~ translate(lhs) ~ ` ` ~ operator ~ ` ` ~ translate(rhs) ~ `) {`] ~
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
        return [`throw new Exception(` ~ embedded.children[0 .. $-1].map!translate.join(` ~ `) ~ `);`];

    case "Makefile.PlusEqual":
        auto var = statement.children[0].matches.join;
        auto val = translate(statement.children[1]);
        return [makeVar(var) ~ ` = (` ~ consultVar(var) ~ `.split(" ") ~ ` ~ val ~ `).join(" ");`];

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
    auto val = statement.children.length > 1 ? translate(statement.children[1]) : `""`;
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


string translate(in ParseTree expression) {
    switch(expression.name) {
    case "Makefile.Expression":
        return expression.children.map!translate.join(` ~ `);
    case "Makefile.Function":
        return translateFunction(expression);
    case "Makefile.Variable":
        return `consultVar("` ~ unsigil(expression.matches.join) ~ `")`;
    case "Makefile.String":
    case "Makefile.EmptyString":
        return translateLiteralString(expression.matches.join);
    default:
        throw new Exception("Unknown expression " ~ expression.name);
    }
}

string translateFunction(in ParseTree function_) {
    auto name = function_.children[0].matches.join;
    switch(name) {
    case "addsuffix":
        auto suffix = translate(function_.children[1]);
        auto names = translate(function_.children[2]);
        return names ~ `.split(" ").map!(a => a ~ ` ~ suffix ~ `).array.join(" ")`;

    case "addprefix":
        auto prefix = translate(function_.children[1]);
        auto names = translate(function_.children[2]);
        return names ~ `.split(" ").map!(a => ` ~ prefix ~ ` ~ a).array.join(" ")`;

    case "subst":
        auto from = translate(function_.children[1]);
        auto to = translate(function_.children[2]);
        auto text = translate(function_.children[3]);
        return text ~ `.replace(` ~ from ~ `, ` ~ to ~ `)`;

    case "if":
        auto cond = translate(function_.children[1]);
        auto trueBranch = translate(function_.children[2]);
        auto elseBranch = function_.children.length > 3 ? translate(function_.children[3]) : `""`;
        return cond ~ ` != "" ? ` ~ trueBranch ~ ` : ` ~ elseBranch;

    case "findstring":
        return `findstring(` ~ translate(function_.children[1]) ~ `, ` ~ translate(function_.children[2]) ~ `)`;

    case "shell":
        return `executeShell(` ~ translate(function_.children[1]) ~ `).output`;

    default:
        throw new Exception("Unknown function " ~ name);
    }
}

string translateOld(in ParseTree expression) {
    switch(expression.name) {
    case "Makefile.Expression":
    case "Makefile.EmbeddedString":
    case "Makefile.SpaceArgExpression":
        return expression.children.map!translate.join(` ~ `);
    case "Makefile.LiteralString":
    case "Makefile.ArgString":
    case "Makefile.NonEmptyString":
    case "Makefile.FreeFormString":
    case "Makefile.SpaceArgString":
        return translateLiteralString(expression.matches.join);
    case "Makefile.Variable":
        return `consultVar("` ~ unsigil(expression.matches.join) ~ `", "")`;
    case "Makefile.Function":
    case "Makefile.FuncArg":
    case "Makefile.FuncLastArg":
        return expression.children.length ? translate(expression.children[0]) : translateLiteralString(expression.matches.join);
    case "Makefile.Shell":
        return `executeShell(` ~ translate(expression.children[0]) ~ `).output`;
    case "Makefile.FindString":
        return `findstring(` ~ translate(expression.children[0]) ~ `, ` ~ translate(expression.children[1]) ~ `)`;
    case "Makefile.IfFunc":
        auto cond = translate(expression.children[0]);
        auto trueBranch = translate(expression.children[1]);
        auto falseBranch = `""`;
        return cond ~ ` != "" ? ` ~ trueBranch ~ ` : ` ~ falseBranch;
    case "Makefile.Subst":
        auto from = expression.children[0];
        auto to = expression.children[1];
        auto text = expression.children[2];
        return translate(text) ~ `.replace(` ~ translate(from) ~ `, ` ~ translate(to) ~ `)`;

    case "Makefile.AddPrefix":
        auto prefix = expression.children[0];
        auto names = expression.children[1..$];
        return `[` ~ names.map!translate.join(", ") ~ `].map!(a => ` ~ translate(prefix) ~ ` ~ a).array.join(" ")`;

    case "Makefile.AddSuffix":
        auto suffix = expression.children[0];
        auto names = expression.children[1..$];
        return `[` ~ names.map!translate.join(", ") ~ `].map!(a => a ~ ` ~ translate(suffix) ~ `).array.join(" ")`;


    default:
        throw new Exception("Unknown expression " ~ expression.name);
    }
}

string translateLiteralString(in string str) {
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
        //pragma(msg, code);
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

@("Top-level assignment to nothing") unittest {
    mixin TestMakeToReggae!(["QUIET:="]);
    makeVarShouldBe!"QUIET"("");
}


@("Comments are not ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "\n"
        "\n"
        "QUIET:=true\n");
    "// this is a comment".shouldBeIn(toReggaeLines(parseTree));
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


@("shell function no user vars Darwin") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,$(OS))",
         "  uname_S:=$(shell uname -s)",
         "  ifeq (Darwin,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ]);
    version(Linux) {
        makeVarShouldBe!"uname_S"("Linux");
        makeVarShouldNotBeSet!"OS";
    } else {}
}

@("shell function no user vars Linux") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (,$(OS))",
         "  uname_S:=$(shell uname -s)",
         "  ifeq (Linux,$(uname_S))",
         "    OS:=DefinitelyLinux",
         "  endif",
         "endif",
            ]);
    version(Linux) {
        makeVarShouldBe!"uname_S"("Linux");
        makeVarShouldBe!"OS"("DefinitelyLinux");
    } else {}
}

@("shell function with user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["OS": "Linux"],
        ["ifeq (,$(OS))",
         "  uname_S:=$(shell uname -s)",
         "  ifeq (Linux,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ]);
    version(Linux) {
        makeVarShouldNotBeSet!"uname_S";
        makeVarShouldNotBeSet!"OS";
    } else {}
}

@("error function with no vars") unittest {
    try {
        mixin TestMakeToReggae!(
            ["ifeq (,$(MODEL))",
             "  $(error Model is not set for $(foo))",
             "endif",
                ]);
        assert(0, "Should never get here");
    } catch(Throwable t) {}
}

@("error function with user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["MODEL": "64"],
        ["ifeq (,$(MODEL))",
         "  $(error Model is not set for $(foo))",
         "endif",
            ]);
}


@("ifneq no user vars") unittest {
    mixin TestMakeToReggae!(
        ["ifneq (,$(FOO))",
         "  FOO_SET:=1",
         "endif",
            ]);
    makeVarShouldNotBeSet!"FOO_SET";
}

@("ifneq no user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["FOO": "BAR"],
        ["ifneq (,$(FOO))",
         "  FOO_SET:=1",
         "endif",
            ]);
    makeVarShouldBe!"FOO_SET"("1");
}

@("findstring") unittest {
    mixin TestMakeToReggae!(
        ["uname_S:=Linux",
         "uname_M:=x86_64",
         "is64:=$(findstring $(uname_M),x86_64 amd64)",
         "isMac:=$(findstring $(uname_S),Darwin MACOS AppleStuff)",
            ]);
    makeVarShouldBe!"is64"("x86_64");
    makeVarShouldBe!"isMac"("");
}

@("override with if and no user vars") unittest {
    mixin TestMakeToReggae!(["override PIC:=$(if $(PIC),-fPIC,)"]);
    makeVarShouldBe!"PIC"("");
}

@("override with if and user vars") unittest {
    mixin TestMakeToReggaeUserVars!(["PIC": "foo"], ["override PIC:=$(if $(PIC),-fPIC,)"]);
    makeVarShouldBe!"PIC"("-fPIC");
}


@("+= var not set") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["BUILD": "debug"],
        ["ifeq ($(BUILD),debug)",
         "  CFLAGS += -g",
         "endif",
            ]);
    makeVarShouldBe!"CFLAGS"("-g");
}


@("+= var set") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["BUILD": "debug"],
        ["CFLAGS:=-O0",
         "ifeq ($(BUILD),debug)",
         "  CFLAGS += -g",
         "endif",
            ]);
    makeVarShouldBe!"CFLAGS"("-O0 -g");
}


@("subst") unittest {
    mixin TestMakeToReggae!(["P2LIB=$(subst ee,EE,feet on the street)"]);
    makeVarShouldBe!"P2LIB"("fEEt on the strEEt");
}

@("addprefix") unittest {
    mixin TestMakeToReggae!(["FOO=$(addprefix std/,algorithm container)"]);
    makeVarShouldBe!"FOO"("std/algorithm std/container");
}

@("addsuffix") unittest {
    mixin TestMakeToReggae!(["FOO=$(addsuffix .c,foo bar)"]);
    makeVarShouldBe!"FOO"("foo.c bar.c");
}

@("addsuffix subst no user vars") unittest {
    mixin TestMakeToReggae!(["FOO=$(addsuffix $(DOTLIB),$(subst ee,EE,feet on the street))"]);
    makeVarShouldBe!"FOO"("fEEt on the strEEt");
}


@("addsuffix subst with user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["DOTLIB": ".a"],
        ["FOO=$(addsuffix $(DOTLIB),$(subst ee,EE,feet on the street))"]);
    makeVarShouldBe!"FOO"("fEEt.a on.a the.a strEEt.a");
}


@("addprefix addsuffix subst no user vars") unittest {
    mixin TestMakeToReggae!(["P2LIB=$(addprefix $(ROOT),$(addsuffix $(DOTLIB),$(subst ee,EE,feet on the street)))"]);
    makeVarShouldBe!"P2LIB"("fEEt on the strEEt");
}

@("addprefix addsuffix subst with user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["ROOT": "leroot/", "DOTLIB": ".a"],
        ["P2LIB=$(addprefix $(ROOT),$(addsuffix $(DOTLIB),$(subst ee,EE,feet on the street)))"]);
    makeVarShouldBe!"P2LIB"("leroot/fEEt.a leroot/on.a leroot/the.a leroot/strEEt.a");
}
