module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Elements            <- Element*
    Element             <- ConditionBlock / Line
    Line                <- SimpleAssignment / RecursiveAssignment / Override / Error / Include / Comment / Empty
    ConditionBlock      <- (IfEqual / IfNotEqual) Else? EndIf
    Else                <- Spacing "else" endOfLine Element+
    IfEqual             <- Spacing "ifeq" Spacing "(" IfArg "," IfArg ")" endOfLine Element+
    IfNotEqual          <- Spacing "ifneq" Spacing "(" IfArg "," IfArg ")" endOfLine Element+
    IfArg               <- Spacing FindString / Spacing "$(" (!")" .)* ")" / Spacing identifier / ""
    FindString          <- "$(findstring " FindStringNeedle "," FindStringHaystack ")"
    FindStringNeedle    <- Variable / (!"," .)*
    FindStringHaystack  <- Variable / (!")" .)*
    Variable            <- "$(" (!")" .)* ")"
    EndIf               <- Spacing "endif" endOfLine
    SimpleAssignment    <- Spacing VariableDecl Spacing ":=" (!endOfLine .)* endOfLine
    RecursiveAssignment <- Spacing VariableDecl Spacing "=" Spacing? (!endOfLine .)* endOfLine
    VariableDecl        <- identifier
    VariableValue       <- IfFunc / (!endOfLine .)* endOfLine
    IfFunc              <- "$(if " FuncArg "," FuncArg "," FuncLastArg ")" endOfLine
    FuncArg             <- Variable / (!"," .)*
    FuncLastArg         <- Variable / (!")" .)*
    Include             <- "include" Spacing FileName endOfLine
    FileName            <- FileNameChar*
    FileNameChar        <- [a-zA-Z_0-9./]
    Error               <- Spacing "$(error " (!endOfLine .)* endOfLine
    Override            <- "override " VariableDecl ("=" / ":=") VariableValue
    Comment             <- Spacing "#" (!endOfLine .)* endOfLine
    Empty               <- endOfLine / Spacing endOfLine
`));
