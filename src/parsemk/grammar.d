module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Elements            <- Element*
    Element             <- ConditionBlock / Line
    Line                <- SimpleAssignment / RecursiveAssignment / Error / Include / Ignore
    ConditionBlock      <- IfEqual Else? EndIf
    Else                <- Spacing "else" endOfLine Element+
    IfEqual             <- Spacing "ifeq" Spacing "(" VarStringEmpty "," VarStringEmpty ")" endOfLine Element+
    VarStringEmpty      <- Spacing "$(" (!")" .)* ")" / Spacing identifier / ""
    EndIf               <- Spacing "endif" endOfLine
    SimpleAssignment    <- Spacing Variable ":=" (!endOfLine .)* endOfLine
    RecursiveAssignment <- Spacing Variable "=" (!endOfLine .)* endOfLine
    Variable            <- identifier
    Include             <- "include" Spacing FileName endOfLine
    FileName            <- FileNameChar*
    FileNameChar        <- [a-zA-Z_0-9./]
    Error               <- Spacing "$(error " (!")" .)* ")" endOfLine
    Ignore              <- Comment / Empty
    Comment             <- Spacing "#" (!endOfLine .)* endOfLine
    Empty               <- endOfLine / Spacing endOfLine
`));
