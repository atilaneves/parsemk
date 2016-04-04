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

string toReggaeOutput(ParseTree parseTree) {
    return ([`import reggae;`] ~
            `string[string] makeVars; // dynamic variables` ~
            `auto _getBuild() {` ~
            toReggaeLines(parseTree).map!(a => "    " ~ a).array ~
            `}`).join("\n");
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

private string[] newMakeVar(ref Environment environment, in string var, in string val) {
    environment.bindings[var] = true;
    return [consultMakeVar(var) ~ ` = ` ~ val ~ `;`];
}

// resolve variables (e.g. $(FOO)) and make built-in functions such as $(shell)
private string resolveVariablesInValue(in string val) {
    string replacement = val;

    auto shellRe = regex(`\$\(shell (.+)\)`, "g");
    replacement = replacement.replaceAll(shellRe, `" ~ executeShell("$1").output ~ "`);

    auto varRe = regex(`\$\((.+)\)`, "g");
    replacement = replacement.replaceAll(varRe, `" ~ makeVars["$1"] ~ "`);

    auto ret = `"` ~ replacement ~ `"`;
    ret = ret.replaceAll(regex(`^"" ~ `), "");
    ret = ret.replaceAll(regex(` ~ ""`), "");
    return ret;
}

// e.g. $(FOO) -> FOO
private string unsigil(in string var) {
    return var[2 .. $ - 1];
}

private string[] assignmentToReggae(in ParseTree element, ref Environment environment, bool topLevel) {
    auto assignment = element.children[0];

    auto var   = assignment.matches[0];
    auto value = "";
    if(assignment.matches.length > 3) {
        value = assignment.matches[2 .. $-1].join;
    }
    value = resolveVariablesInValue(value);
    return topLevel
        ? newMakeVar(environment, var, `userVars.get("` ~ var ~ `", ` ~ value ~ `)`)
        : newMakeVar(environment, var, value);
}


string[] elementToReggae(in ParseTree element, ref Environment environment, bool topLevel = true) {
    switch(element.children[0].name) {
    case "Makefile.SimpleAssignment":
    case "Makefile.RecursiveAssignment":
        return assignmentToReggae(element, environment, topLevel);

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

    case "Makefile.Error":
        auto error = element.children[0];
        // slice: skip "$(error " and ")\n"
        return [`throw new Exception("` ~ element.matches[1 .. $-2].join ~ `");`];

    case "Makefile.ConditionBlock":
        auto cond = element.children[0];
        auto ifBlock = cond.children[0];

        string lookup(string name) {
            if(!name.startsWith("$(")) return `"` ~ name ~ `"`;
            name = unsigil(name);
            return name in environment.bindings
                               ? consultMakeVar(name)
                               : `userVars.get("` ~ name.replaceAll(regex(`\$\((.+)\)`), `$1`) ~ `", "")`;
        }

        auto lhs = lookup(ifBlock.children[0].matches.join);
        auto rhs = lookup(ifBlock.children[1].matches.join);

        // 2: skip the two sides (lhs, rhs) being compared
        auto ifElements = ifBlock.children[2..$];
        auto elseElements = cond.children.length > 2 ? cond.children[1].children : [];

        string[] flatMapToReggae(in ParseTree[] elements) {
            return elements.map!(a => elementToReggae(a, environment, false)).join.map!(a => "    " ~ a).array;
        }

        auto elseResult = flatMapToReggae(elseElements);
        return
            [`if(` ~ lhs ~ ` == ` ~ rhs ~ `) {`] ~
            flatMapToReggae(ifElements) ~
            (elseResult.length ? [`} else {`] : []) ~
            elseResult ~
            `}`;

    default:
        throw new Exception("Unknown/Unimplemented parser " ~ element.children[0].name);
    }
}


@("Variable assignment with := to auto QUIET") unittest {
    auto parseTree = Makefile("QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["QUIET"] = userVars.get("QUIET", "true");`]);
}

@("Variable assignment with := to auto FOO") unittest {
    auto parseTree = Makefile("FOO:=bar\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["FOO"] = userVars.get("FOO", "bar");`]);
}

@("Comments are ignored") unittest {
    auto parseTree = Makefile(
        "# this is a comment\n"
        "QUIET:=true\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["QUIET"] = userVars.get("QUIET", "true");`]);
}


@("Variables can be assigned to nothing") unittest {
    auto parseTree = Makefile("QUIET:=\n");
    toReggaeLines(parseTree).shouldEqual(
        [`makeVars["QUIET"] = userVars.get("QUIET", "");`]);
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
        [`makeVars["OS"] = userVars.get("OS", "solaris");`]);
}

@("ifeq works correctly with no else block") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "OS=osx",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == userVars.get("OS", "")) {`,
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
        [`if("MACOS" == userVars.get("OS", "")) {`,
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
        [`if("" == userVars.get("BUILD", "")) {`,
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
        [`if("MACOS" == userVars.get("OS", "")) {`,
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
        [`if("" == userVars.get("OS", "")) {`,
         `    makeVars["uname_S"] = "Linux";`,
         `    if("Darwin" == makeVars["uname_S"]) {`,
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
        [`if("" == userVars.get("MODEL", "")) {`,
         `    makeVars["MODEL"] = "64";`,
         `}`,
         `makeVars["MODEL_FLAG"] = userVars.get("MODEL_FLAG", "-m" ~ makeVars["MODEL"]);`,
            ]);
}


@("shell commands get translated to a module constructor") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(OS))",
         "  uname_S:=$(shell uname -s)",
         "  ifeq (Darwin,$(uname_S))",
         "    OS:=osx",
         "  endif",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == userVars.get("OS", "")) {`,
         `    makeVars["uname_S"] = executeShell("uname -s").output;`,
         `    if("Darwin" == makeVars["uname_S"]) {`,
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
        [`if("MACOS" == userVars.get("OS", "")) {`,
         `    makeVars["OS"] = "osx";`,
         `}`,
         `if("" == userVars.get("MODEL", "")) {`,
         `    if(makeVars["OS"] == "solaris") {`,
         `        makeVars["uname_M"] = executeShell("isainfo -n").output;`,
         `    }`,
         `}`,
            ]);
}

@("error function") unittest {
    auto parseTree = Makefile(
        ["ifeq (,$(MODEL))",
         "  $(error Model is not set)",
         "endif",
            ].join("\n") ~ "\n");
    toReggaeLines(parseTree).shouldEqual(
        [`if("" == userVars.get("MODEL", "")) {`,
         `    throw new Exception("Model is not set");`,
         `}`,
            ]);
}
