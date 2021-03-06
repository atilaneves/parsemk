module parsemk.reggae;

import parsemk.grammar;
import pegged.grammar;
import reggae.build;
import std.array;
import std.exception;
import std.stdio;
import std.file;
import std.algorithm;
import std.regex;



version(unittest) {
    import unit_threaded;
    import reggae.ctaa;
}
else {
    enum Serial;
    enum ShouldFail;
}


string toReggaeOutputWithImport(in string fileName, ParseTree parseTree) {
    return "import reggae;\n" ~ toReggaeOutput(fileName, parseTree);
}

string toReggaeOutput(in string fileName, ParseTree parseTree) {
    auto header = q{
/**
 Automatically generated from parsing a Makefile, do not edit by hand
 */

import std.algorithm;
import std.process;
import std.path;
import std.string;
import std.array;
import std.path;

string[string] makeVars; // dynamic variables

string _var(in string var) {
    return makeVars.get(var, userVars.get(var, ""));
}


// implementation of GNU make $(findstring)
string findstring(in string needle, in string haystack) {
    return haystack.canFind(needle) ? needle : "";
}

// implementation of GNU make $(firstword)
string firstword(in string words) {
    auto bySpace = words.split;
    return bySpace.length ? bySpace[0] : "";
}

}; //end of q{}

    auto lines = toReggaeLines(fileName, parseTree);
     return header ~
         patternLines(parseTree).join("\n") ~
         "Build _getBuild() {\n" ~
         "    makeVars = userVars.toAA;\n" ~
         lines.map!(a => "    " ~ a).join("\n") ~ "\n" ~
         "}\n";
}

string[] patternLines(in ParseTree parseTree) {
    import std.conv;
    import std.range;


    enforce(parseTree.name == "Makefile", "Unexpected parse tree grammar " ~ parseTree.name);
    enforce(parseTree.children.length == 1,
            text("Top-level node has too many children (", parseTree.children.length, ")"));
    auto statements = parseTree.children[0];

    enforce(statements.name == "Makefile.Statements",
            text("Unexpected node ", parseTree.name, " expected Statements"));

    auto patternBlocks = statements.children.
        retro.
        filter!(a => isTargetBlock(a)).
        filter!(a => isPatternRule(a)).
        array;

    string[] lines;

    lines ~= "Target[] patternInputs(string inputsStr) {";
    lines ~= `    import std.regex: regex, matchFirst;`;
    lines ~= `    auto inputs = inputsStr.split;`;
    if(!patternBlocks.empty) {
        auto foreach_ = `    foreach(patternRule; [` ~
            patternBlocks.map!(a => `[` ~  [targetOutputs(a),
                                            targetCommand(a),
                                            targetInputs(a)].join(`, `) ~ `]`).join(`, `) ~ `]) {`;
        lines ~= foreach_;
        lines ~= `        auto reg = regex(patternRule[0].replace(".", "\\.").replace("%", "(.*?)"));`;
        lines ~= `        if(inputs.all!(a => a.matchFirst(reg))) {`;
        lines ~= `            return inputs.map!(a => Target(patternRule[0].replace("%", a.matchFirst(reg)[1]), patternRule[1], [patternRule[2].replace("%", a.matchFirst(reg)[1])].map!(a => Target(a)).array)).array;`;
        lines ~= `        }`;
        lines ~= `    }`;
    }
    lines ~= `    return inputs.map!(a => Target(a)).array;`;
    lines ~= "}";
    lines ~= "";
    lines ~= "";

    return lines;
}

bool isTargetBlock(in ParseTree tree) {
    if(tree.name == "Makefile.TargetBlock") return true;
    return reduce!((a, b) => a || isTargetBlock(b))(false, tree.children);
}

string[] toReggaeLines(in string fileName, ParseTree parseTree) {
    import std.conv;
    import std.range;


    enforce(parseTree.name == "Makefile", "Unexpected parse tree grammar " ~ parseTree.name);
    enforce(parseTree.children.length == 1,
            text("Top-level node has too many children (", parseTree.children.length, ")"));
    auto statements = parseTree.children[0];

    enforce(statements.name == "Makefile.Statements",
            text("Unexpected node ", parseTree.name, " expected Statements"));

    string[] lines;

    // first, process everything that's not a Make target, since those need
    // to be declared back to front
    foreach(statement; statements.children.filter!(a => !isTargetBlock(a))) {
        enforce(statement.name == "Makefile.Statement",
                text("Unexpected parse tree ", statement.name, " expected Statement"));
        lines ~= statementToReggaeLines(fileName, statement, true);
    }

    auto targetBlocks = statements.children.retro.filter!(a => isTargetBlock(a)).array;

    lines ~= targetsToReggaeLines(fileName, targetBlocks);

    return lines;
}

private string[] targetsToReggaeLines(in string fileName, in ParseTree[] targetBlocks) {
    import std.range;
    import std.conv;

    if(targetBlocks.empty) {
        return [`return Build();`];
    }

    string[] lines;

    lines ~= declareTargets(targetBlocks);

    auto defaultTarget = targetBlocks[$ - 1];
    auto otherTargets = targetBlocks[0 .. $ - 1];

    foreach(statement; otherTargets) {
        enforce(statement.name == "Makefile.Statement",
                text("Unexpected parse tree ", statement.name, " expected Statement"));
        lines ~= statementToReggaeLines(fileName, statement, true, otherTargets, false);
    }

    lines ~= statementToReggaeLines(fileName, defaultTarget, true, otherTargets, true);

    if(!lines.canFind!(a => a.canFind("return Build"))) {
        auto targetsStr = chain([targetName(defaultTarget)],
                                otherTargets.filter!(a => !isPatternRule(a)).
                                map!(a => `optional(` ~ targetName(a) ~ `)`));
        lines ~= [`return Build(` ~ targetsStr.join(", ") ~ `);`];
    }

    return lines;
}


// e.g. $(FOO) -> FOO
private string unsigil(in string var) {
    if(var[0] != '$') return var;
    return var[1] == '(' ? var[2 .. $ - 1] : var[1 .. $];
}

@("unsigil regular variable") unittest {
    "$(FOO)".unsigil.shouldEqual("FOO");
}

@("unsigil index variable") unittest {
    "$1".unsigil.shouldEqual("1");
}


string[] statementToReggaeLines(in string fileName, in ParseTree statement, bool topLevel = true,
                                in ParseTree[] others = [], bool firstTarget = false) {
    import std.path;

    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.SimpleStatement":
    case "Makefile.CompoundStatement":
        return statementToReggaeLines(fileName, statement.children[0], topLevel, others, firstTarget);

    case "Makefile.ConditionBlock":
        auto ifBlock = statement.children[0];
        // one of the sides could be empty
        auto numExpressions = ifBlock.children.count!(a => a.name == "Makefile.Expression");
        auto lhs = ifBlock.children[0];
        auto rhs = numExpressions > 1 ? ifBlock.children[1] : ParseTree("Makefile.String");
        auto firstStatementIndex = ifBlock.children.countUntil!(a => a.name == "Makefile.Statement");
        auto ifStatements = ifBlock.children[firstStatementIndex .. $];
        auto operator = ifBlock.name == "Makefile.IfEqual" ? "==" : "!=";
        string[] mapInnerStatements(in ParseTree[] statements) {
            return statements.
                map!(a => statementToReggaeLines(fileName, a, false, others, firstTarget)).
                join.
                map!(a => "    " ~ a).
                array;
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
        auto incFileName = buildPath(dirName(fileName), fileNameTree.matches.join);
        auto input = cast(string)read(incFileName);
        // get rid of the `return Build()` line with $ - 1
        return toReggaeLines(fileName, Makefile(input))[0 .. $ - 1];

    case "Makefile.Comment":
        // the slice gets rid of the "#" character
        return [`//` ~ statement.matches[1..$].join];

    case "Makefile.Error":
        auto msg = translate(statement.children[0]);
        return [`throw new Exception(` ~ msg ~ `);`];

    case "Makefile.PlusEqual":
        auto var = statement.children[0].matches.join;
        auto val = translate(statement.children[1]);
        return [makeVar(var) ~ ` = (` ~ consultVar(`"` ~ var ~ `"`) ~ `.split ~ ` ~ val ~ `).join(" ");`];

    case "Makefile.TargetBlock":
        return targetBlockToReggaeLines(statement, firstTarget, others);

    case "Makefile.Empty":
        return [];

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ statement.name);
    }
}

// since D needs to declare variables before they're assigned...
private string[] declareTargets(in ParseTree[] targetBlocks) {
    return targetBlocks.
        filter!(a => !isPatternRule(a) && !isPhonyRule(a)).
        map!(a => `Target ` ~ targetName(a) ~ `;`).
        array;
}


private string translateCommand(in ParseTree statement) {
    if(statement.name != "Makefile.TargetBlock") return `""`;

    auto fromFirstCommand = statement.children.find!(a => a.name == "Makefile.CommandLine");
    auto command = fromFirstCommand.map!translate.join(` ~ ";" ~ `);
    return command == "" ? `""` : command;
}

private bool isPatternRule(in ParseTree statement) {
    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.CompoundStatement":
        return statement.children.fold!((a, b) => a || isPatternRule(b))(false);
    case "Makefile.TargetBlock":
        auto fromOutputs  = statement.children.find!(a => a.name == "Makefile.Outputs");
        return !fromOutputs.empty && fromOutputs.front.translate.canFind("%");
    default:
        return false;
    }
}

private bool isPhonyRule(in ParseTree statement) {
    return targetName(statement) == ".PHONY";
}

private string unquote(in string str) {
    if(str[0] == '"') return str[1 .. $-1];
    return str;
}

private string targetOutputs(in ParseTree statement) {
    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.CompoundStatement":
        return targetOutputs(statement.children[0]);
    case "Makefile.TargetBlock":
        return translate(statement.children[0]);
    default:
        throw new Exception("Cannot get pattern for ", statement.matches.join);
    }
}

private string targetInputs(in ParseTree statement) {
    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.CompoundStatement":
        return targetInputs(statement.children[0]);
    case "Makefile.TargetBlock":
        return translate(statement.children[1]);
    default:
        throw new Exception("Cannot get pattern for ", statement.matches.join);
    }
}

private string targetCommand(in ParseTree statement) {
    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.CompoundStatement":
        return targetCommand(statement.children[0]);
    case "Makefile.TargetBlock":
        return translate(statement.children[2]);
    default:
        throw new Exception("Cannot get pattern for ", statement.matches.join);
    }
}



private string[] targetBlockToReggaeLines(in ParseTree statement, bool firstTarget, in ParseTree[] others) {
    import std.string;
    import std.range;

    if(isPatternRule(statement)) return [];
    if(isPhonyRule(statement)) return [];

    auto command = translateCommand(statement);

    if(firstTarget && command == `""`) {
        auto inputs  = statement.children[1].matches.join.split;
        return [`return Build(` ~  inputs.join(", ") ~ `);`];
    }

    auto fromInputs = statement.children.find!(a => a.name == "Makefile.Inputs");
    string inputsStr = `[]`;

    if(!fromInputs.empty) {
        auto names = ([statement] ~ others).map!(a => targetName(a)).array;

        // check to see if one dependency that is a variable name
        auto var = unsigil(fromInputs.front.matches.join);

        // check if any pattern rules match
        auto targetBlocks = [statement] ~ others;
        auto patterns = targetBlocks.filter!(a => isPatternRule(a));

        auto inputs = fromInputs.front.translate;

        if(names.canFind(var))
            inputsStr = `[` ~ var ~ `]`; //use the variable name then
        else if(!patterns.empty) {
            inputsStr = `patternInputs(` ~ inputs ~ `)`;
        }
        else
            inputsStr = `(` ~ inputs ~ `).split.map!(a => Target(a)).array`;
    }

    auto fromOutputs  = statement.children.find!(a => a.name == "Makefile.Outputs");
    auto outputsStr = fromOutputs.empty
        ? `""`
        : `(` ~ fromOutputs.front.translate ~ `).split.array`;

    auto params = [outputsStr, command, inputsStr];
    auto targetLine = targetName(statement) ~ ` = Target(` ~ params.join(", ") ~ `);`;
    return [targetLine];
}


private string targetName(in ParseTree statement) {
    import std.string;
    switch(statement.name) {
    case "Makefile.Statement":
    case "Makefile.CompoundStatement":
    case "Makefile.ConditionBlock":
        return targetName(statement.children[0]);
    case "Makefile.IfEqual":
    case "Makefile.IfNotEqual":
        return targetName(statement.children[$ - 1]);

    case "Makefile.TargetBlock":
        return unsigil(statement.children[0].matches.join.split.join("_"));
    default:
        throw new Exception("Cannot get target name from statement of type " ~ statement.name);
    }
}

@("targetName with sigil") unittest {
    auto name = targetName(ParseTree("Makefile.TargetBlock", true, [], "", 0, 0,
                                     [ParseTree("Makefile.Inputs", true, ["$(LIB)"])]));
    name.shouldEqual("LIB");
}

private string[] assignmentLines(in ParseTree statement, in bool topLevel) {
    bool anyIndexVariables = statement.children.length > 1 && anyIndexVariableIn(statement.children[1]);
    return anyIndexVariables ? functionAssignmentLines(statement) : normalAssignmentLines(statement, topLevel);
}

private string[] normalAssignmentLines(in ParseTree statement, in bool topLevel) {
    // assignments at top-level need to consult userVars in order for
    // the values to be overridden at the command line.
    // assignments elsewhere unconditionally set the variable
    auto var = statement.children[0].matches.join;
    auto val = statement.children.length > 1 ? translate(statement.children[1]) : `""`;
    // HACK: Get rid of empty space at the beginning if any (couldn't get the grammar to get rid of it)
    if(val.startsWith(`" `)) val = `"` ~ val[2..$];
    return topLevel
        ? [makeVar(var) ~ ` = userVars.get("` ~ var ~ `", ` ~ val ~ `);`]
        : [makeVar(var) ~ ` = ` ~ val ~ `;`];
}

// assignment to a variable that's to be used as a function
private string[] functionAssignmentLines(in ParseTree statement) {
    auto func = statement.children[0].matches.join;
    auto val = statement.children.length > 1 ? translate(statement.children[1]) : `""`;
    return [`string ` ~ func ~ `(string[] params ...) {`,
            `    return ` ~ val ~ `;`,
            `}`,
        ];
}

private bool anyIndexVariableIn(in ParseTree expression) {
    if(expression.name == "Makefile.IndexVariable") return true;
    if(expression.children.empty) return false;
    return reduce!((a, b) => a || anyIndexVariableIn(b))(false, expression.children);
}

private string makeVar(in string varName) {
    return `makeVars["` ~ varName ~ `"]`;
}

private string consultVar(in string varName) {
    return `_var(` ~ varName ~ `)`;
}

string translate(in ParseTree expression) {
    import std.conv;

    switch(expression.name) {
    case "Makefile.Expression":
    case "Makefile.ErrorExpression":
    case "Makefile.Variable":
    case "Makefile.CommandLine":
    case "Makefile.Inputs":
    case "Makefile.Outputs":
        if(expression.children.empty) return "";

        auto expressionBeginsWithSpace = expression.children[0].name == "Makefile.String" &&
                                         expression.children[0].matches.join == " ";
        auto children = expressionBeginsWithSpace ? expression.children[1..$] : expression.children;
        return children.map!translate.join(` ~ `);
    case "Makefile.Function":
        return translateFunction(expression);
    case "Makefile.NormalVariable":
        return translateVariable(expression);
    case "Makefile.IndexVariable":
        return `params[` ~ unsigil(expression.matches.join) ~ `]`;
    case "Makefile.ForEachVariable":
        return unsigil(expression.matches.join);
    case "Makefile.String":
    case "Makefile.ErrorString":
        return translateLiteralString(expression.matches.join);
    default:
        throw new Exception("Unknown expression " ~ expression.name ~ " in '" ~ expression.matches.join ~ "'");
    }
}

string translateVariable(in ParseTree expression) {
    switch(expression.matches.join) {
    case "$@":
        return `"$out"`;
    case "$<":
        return `"$in"`;
    default:
        return consultVar(expression.children.map!translate.join);
    }
}

string translateFunction(in ParseTree function_) {
    auto name = function_.children[0].matches.join;
    switch(name) {
    case "addsuffix":
        auto suffix = translate(function_.children[1]);
        auto names = translate(function_.children[2]);
        return `(` ~ names ~ `).split.map!(a => a ~ ` ~ suffix ~ `).join(" ")`;

    case "addprefix":
        auto prefix = translate(function_.children[1]);
        auto names = translate(function_.children[2]);
        return `(` ~ names ~ `).split.map!(a => ` ~ prefix ~ ` ~ a).join(" ")`;

    case "subst":
        auto from = translate(function_.children[1]);
        auto to = translate(function_.children[2]);
        auto text = translate(function_.children[3]);
        return `(` ~ text ~ `).replace(` ~ from ~ `, ` ~ to ~ `)`;

    case "if":
        auto cond = translate(function_.children[1]);
        auto trueBranch = translate(function_.children[2]);
        auto elseBranch = function_.children.length > 3 ? translate(function_.children[3]) : `""`;
        return cond ~ ` != "" ? ` ~ trueBranch ~ ` : ` ~ elseBranch;

    case "findstring":
        return `findstring(` ~ translate(function_.children[1]) ~ `, ` ~ translate(function_.children[2]) ~ `)`;

    case "shell":
        return `executeShell(` ~ translate(function_.children[1]) ~ `).output.chomp`;

    case "basename":
        return `stripExtension(` ~ translate(function_.children[1]) ~ `)`;

    case "call":
        auto callee = function_.children[1].matches.join;
        auto params = function_.children[2 .. $].map!translate.join(`, `);
        return callee ~ `("` ~ callee ~ `", ` ~ params ~ `)`;

    case "foreach":
        auto var = function_.children[1].matches.join;
        auto list = translate(function_.children[2]);
        auto body_ = translate(function_.children[3]).
            replace(consultVar(`"` ~ var ~ `"`), var);
        return list ~ `.split.map!(` ~ var ~ ` => ` ~ body_ ~ `).join(" ").stripRight`;

    case "firstword":
        auto text = translate(function_.children[1]);
        return `firstword(` ~ text ~ `)`;

    case "dir":
        return `dirName(` ~ translate(function_.children[1]) ~ `)`;

    default:
        throw new Exception("Unknown function " ~ name);
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
        auto userVars = fromAA(_userVars);
        mixin TestMakeToReggaeNoUserVars!lines;
    }

    mixin template TestMakeToReggae(string[] lines) {
        AssocList!(string, string) userVars;
        mixin TestMakeToReggaeNoUserVars!lines;
    }

    mixin template TestMakeToReggaeNoUserVars(string[] lines) {

        enum parseTree = Makefile(lines.map!(a => a ~ "\n").join);
        enum code = toReggaeOutput("", parseTree);

        //pragma(msg, code);
        mixin(code);

        string access(string var)() {
            return makeVars[var];
        }

        auto _build = _getBuild();

        void makeVarShouldBe(string varName)(string value,
                                             string file = __FILE__, size_t line = __LINE__) {
            attempt(makeVars[varName].shouldEqual(value, file, line));
        }

        void makeVarShouldNotBeSet(string varName)(string file = __FILE__, size_t line = __LINE__) {
            attempt(varName.shouldNotBeIn(makeVars), file, line);
        }

        void buildShouldBe(Build expected, string file = __FILE__, size_t line = __LINE__) {
            attempt(_build.shouldEqual(expected), file, line);
        }

        void attempt(E)(lazy E expr, string file = __FILE__, size_t line = __LINE__) {
            try {
                expr();
            } catch(Throwable t) {
                import std.conv;
                throw new Exception("\n\n" ~
                                    text(parseTree,
                                         "\n----------------------------------------\n",
                                         code,
                                         "----------------------------------------\n") ~
                                    t.toString ~ "\n\n",
                                    file, line);
            }

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
    "// this is a comment".shouldBeIn(toReggaeLines("", parseTree));
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
    toReggaeLines("", parseTree).shouldEqual(
        [`makeVars["OS"] = userVars.get("OS", "solaris");`,
         `return Build();`]);
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
    makeVarShouldBe!"OS"("Windows");
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
    makeVarShouldBe!"BUILD"("debug");
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
    makeVarShouldBe!"OS"("Linux");
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
    } catch(Exception ex) {}
}

@("error function with user vars") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["MODEL": "64"],
        ["ifeq (,$(MODEL))",
         "  $(error Model is not set for $(foo))",
         "endif",
            ]);
}

@("error function as in phobos") unittest {
    try {
        mixin TestMakeToReggae!(
            ["ifneq ($(BUILD),release)",
             "    ifneq ($(BUILD),debug)",
             "        $(error Unrecognized BUILD=$(BUILD), must be 'debug' or 'release')",
             "    endif",
             "endif",
                ]);
    assert(0, "Should never get here");
    } catch(Exception ex) { }
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

@("basename") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["DRUNTIME": "druntime.foo"],
        ["DRUNTIMESO = $(basename $(DRUNTIME)).so.a"]);
    makeVarShouldBe!"DRUNTIMESO"("druntime.so.a");
}

@("define function") unittest {
    mixin TestMakeToReggaeUserVars!(
        ["ROOT": "leroot", "DOTLIB": ".lib", "stuff": "foo/bar/baz toto/titi"],
        ["P2LIB=$(addprefix $(ROOT)/libphobos2_,$(addsuffix $(DOTLIB),$(subst /,_,$1)))",
         "result=$(call P2LIB,$(stuff))"]);
    makeVarShouldBe!"result"("leroot/libphobos2_foo_bar_baz.lib leroot/libphobos2_toto_titi.lib");
}

@("foreach") unittest {
    mixin TestMakeToReggae!(
        ["LIST=foo bar baz",
         "RESULT = $(foreach var,$(LIST),$(addsuffix .c,$(var)))",
         "BAR=BAZ",
            ]);
    makeVarShouldBe!"RESULT"("foo.c bar.c baz.c");
}

@("variable name containing expression") unittest {
    mixin TestMakeToReggae!(
        ["NAME=BAR",
         "FOOBAR=foobar",
         "RESULT=$(FOO$(NAME))",
            ]);
    makeVarShouldBe!"RESULT"("foobar");
}


@("define function with foreach") unittest {
    mixin TestMakeToReggae!(
        ["PACKAGE_std = array ascii base64",
         "P2MODULES=$(foreach P,$1,$(addprefix $P/,$(PACKAGE_$(subst /,_,$P))))",
         // std/algorithm std/container std/digest
         "STD_PACKAGES = std $(addprefix std/,algorithm container digest)",
         "STD_MODULES=$(call P2MODULES,$(STD_PACKAGES))",
            ]);
    makeVarShouldBe!("STD_PACKAGES")("std std/algorithm std/container std/digest");
    makeVarShouldBe!"STD_MODULES"("std/array std/ascii std/base64");
}


@("firstword non-empty") unittest {
    mixin TestMakeToReggae!(["FOO=$(firstword foo bar baz)"]);
    makeVarShouldBe!"FOO"("foo");
}

@("firstword empty") unittest {
    mixin TestMakeToReggae!(
        ["BAR=",
         "FOO=$(firstword $(BAR))"
            ]);
    makeVarShouldBe!"FOO"("");
}


@("first target with no command is considered the Build object") unittest {
    mixin TestMakeToReggae!(
        ["all: foo bar",
         "foo:",
         "\t@echo Foo!",
         "bar:",
         "\t@echo Bar!",
        ]);
    buildShouldBe(Build(Target("foo", "echo Foo!", []), Target("bar", "echo Bar!", [])));
}

@("first target with command is the only one built by default") unittest {
    mixin TestMakeToReggae!(
        ["foo:",
         "\t@echo Foo!",
         "bar:",
         "\t@echo Bar!",
            ]);
    buildShouldBe(Build(Target("foo", "echo Foo!", []),
                        optional(Target("bar", "echo Bar!", []))));
}

@("phobos-like first target in an if block") unittest {
    mixin TestMakeToReggae!(
        ["ifeq (1,$(SHARED))",
         "all : lib dll",
         "else",
         "all : lib",
         "endif",
         "lib:",
         "\t@echo Lib",
         "dll:",
         "\t@echo Dll"
            ]);
    buildShouldBe(Build(Target("lib", "echo Lib", [])));
}

@("Make output special variable") unittest {
    mixin TestMakeToReggae!(
        ["foo: foo.c",
         "\tgcc -o $@ foo.c"
            ]);
    buildShouldBe(Build(Target("foo", "gcc -o $out foo.c", [Target("foo.c")])));
}


@("Inputs should be able to use variables") unittest {
    mixin TestMakeToReggae!(
        ["SRCS=foo.d bar.d",
         "foo: $(SRCS)",
         "\tdmd -of$@ $(SRCS)",
            ]);
    // both the command and the outputs should resolve $(SRCS) to "foo.c"
    buildShouldBe(Build(Target("foo",
                               "dmd -of$out foo.d bar.d",
                               [Target("foo.d"), Target("bar.d")])));

}

@("Outputs should be able to use variables") unittest {
    mixin TestMakeToReggae!(
        ["BIN=foo",
         "$(BIN): foo.d bar.d",
         "\tdmd -of$@ foo.d bar.d",
            ]);
    buildShouldBe(Build(Target("foo",
                               "dmd -of$out foo.d bar.d",
                               [Target("foo.d"), Target("bar.d")])));
}


@("Dependency variables can refer to previously declared targets") unittest {
    mixin TestMakeToReggae!(
        ["LIB=libfoo.a",
         "OBJS=foo.o bar.o",
         "SRCS=toto.d goblin.d",
         "DFLAGS=-g -debug",
         "DMD=dmd",
         "all: lib",
         "lib: $(LIB)",
         "$(LIB): $(OBJS) $(SRCS)",
         "\t$(DMD) $(DFLAGS) -lib -of$@ $(SRCS) $(OBJS)",
            ]);
    auto LIB = Target("libfoo.a",
                      "dmd -g -debug -lib -of$out toto.d goblin.d foo.o bar.o",
                      [Target("foo.o"), Target("bar.o"), Target("toto.d"), Target("goblin.d")]);
    auto lib = Target("lib", "", [LIB]);
    buildShouldBe(Build(lib));
}

@("dir function") unittest {
    mixin TestMakeToReggae!(
        ["DIR=$(dir src/parsemk/reggae.d)",
            ]);
    makeVarShouldBe!"DIR"("src/parsemk");
}

@("pattern rules") unittest {
    mixin TestMakeToReggae!(
        ["app: foo.o bar.o",
         "\tgcc -o $@ $<",
         "%.o: %.c",
         "\tgcc -c $< -o $@",
            ]);
    auto foo = Target("foo.o", "gcc -c $in -o $out", [Target("foo.c")]);
    auto bar = Target("bar.o", "gcc -c $in -o $out", [Target("bar.c")]);
    auto app = Target("app", "gcc -o $out $in", [foo, bar]);
    buildShouldBe(Build(app));
}

@("function call should apply correctly") unittest {
    mixin TestMakeToReggae!(
        ["STD_MODULES=std/array std/ascii std/base64",
         "EXTRA_MODULES_COMMON=std/c/fenv std/c/locale",
         "ALL_D_FILES = $(addsuffix .d, $(STD_MODULES) $(EXTRA_MODULES_COMMON))",
            ]);
    makeVarShouldBe!"ALL_D_FILES"("std/array.d std/ascii.d std/base64.d std/c/fenv.d std/c/locale.d");
}

@("phony is ignored") unittest {
    mixin TestMakeToReggae!(
        ["all: app",
         "app: foo.o bar.o",
         "\tgcc -o $@ $<",
         ".PHONY: all",
            ]);
    buildShouldBe(Build(Target("app", "gcc -o $out $in", [Target("foo.o"), Target("bar.o")])));
}
