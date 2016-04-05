module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Statements        <- Statement*
    Statement         <- CompoundStatement / SimpleStatement endOfLine
    CompoundStatement <- ConditionBlock
    ConditionBlock    <- (IfEqual / IfNotEqual) Else? EndIf
    IfEqual           <- Spacing "ifeq" Spacing "(" Expression "," Spacing Expression ")" endOfLine Statement+
    IfNotEqual        <- Spacing "ifneq" Spacing "(" Expression "," Spacing Expression ")" endOfLine Statement+
    Else              <- Spacing "else" endOfLine Statement+
    EndIf             <- Spacing  "endif" endOfLine
    SimpleStatement   <- Assignment / Include / Comment / Error / Override / Empty
    Assignment        <- Spacing VariableDecl Spacing (":=" / "=") EmbeddedString
    VariableDecl      <- identifier
    Expression     <- Function / Variable / ArgString
    ArgString         <- NonEmptyArgString / EmptyString
    NonEmptyArgString <- (!")" !"," .)+
    Function          <- Shell / FindString / IfFunc
    Shell             <- Spacing "$(shell " NonEmptyString ")"
    FindString        <- Spacing "$(findstring " Expression "," Expression ")"
    IfFunc            <- Spacing "$(if " Expression "," Expression "," Expression ")"
    LiteralString     <- NonEmptyString / EmptyString
    NonEmptyString    <- [a-zA-Z_0-9./\- :]+
    EmptyString       <- ""
    Variable          <- "$(" (!")" .)* ")"
    Comment           <- Spacing "#" (!endOfLine .)*
    Include           <- "include" Spacing FileName
    FileName          <- FileNameChar*
    FileNameChar      <- [a-zA-Z_0-9./]
    Error             <- Spacing "$(error " EmbeddedString
    Override          <- "override " VariableDecl ("=" / ":=") EmbeddedString
    EmbeddedString    <- (Function? Variable? FreeFormString?)*
    FreeFormString    <- (!endOfLine !"$" .)*
    Empty             <- ""
`));
