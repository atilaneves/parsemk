module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
#    Elements            <- Element*
#    Element             <- ConditionBlock / Line
#    Line                <- SimpleAssignment / RecursiveAssignment / Override / Error / Include / Comment / Empty
#    ConditionBlock      <- (IfEqual / IfNotEqual) Else? EndIf
#   Else                <- Spacing "else" endOfLine Element+
#   IfEqual             <- Spacing "ifeq" Spacing "(" IfArg "," IfArg ")" endOfLine Element+
#   IfNotEqual          <- Spacing "ifneq" Spacing "(" IfArg "," IfArg ")" endOfLine Element+
#   IfArg               <- Spacing FindString / Spacing Variable / Spacing identifier / ""
#   Expression          <- Spacing Function / Spacing Variable / Spacing identifier / ""
#   Function            <- Shell / FindString / IfFunc
#   FindString          <- "$(findstring " FuncArg "," FuncLastArg ")"
#   Variable            <- "$(" (!")" .)* ")"
#   EndIf               <- Spacing "endif" endOfLine
#   SimpleAssignment    <- Spacing VariableDecl Spacing ":=" (!endOfLine .)* endOfLine
#   RecursiveAssignment <- Spacing VariableDecl Spacing "=" Spacing? (!endOfLine .)* endOfLine
#   VariableDecl        <- identifier
#   VariableValue       <- IfFunc endOfLine / (!endOfLine .)* endOfLine
#   IfFunc              <- "$(if " FuncArg "," FuncArg "," FuncLastArg ")"
#   FuncArg             <- Variable / (!"," .)*
#   FuncLastArg         <- Variable / (!")" .)*
#   Include             <- "include" Spacing FileName endOfLine
#   FileName            <- FileNameChar*
#   FileNameChar        <- [a-zA-Z_0-9./]
#   Error               <- Spacing "$(error " (!endOfLine .)* endOfLine
#   Override            <- "override " VariableDecl ("=" / ":=") VariableValue
#   Comment             <- Spacing "#" (!endOfLine .)* endOfLine
#   Empty               <- endOfLine / Spacing endOfLine

    Statements        <- Statement*
    Statement         <- CompoundStatement / SimpleStatement endOfLine
    CompoundStatement <- "foobar"
    SimpleStatement   <- Assignment / Comment / Empty
    Assignment        <- Spacing VariableDecl Spacing (":=" / "=") Expression
    VariableDecl      <- identifier
    Expression        <- LiteralString
    LiteralString     <- [a-zA-Z_0-9./]*
    Comment           <- Spacing "#" (!endOfLine .)*
    Empty             <- Spacing
`));
