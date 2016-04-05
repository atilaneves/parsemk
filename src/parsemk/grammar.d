module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Statements        <- Statement*
    Statement         <- CompoundStatement / SimpleStatement endOfLine
    CompoundStatement <- ConditionBlock
    ConditionBlock    <- (IfEqual / IfNotEqual) Else? EndIf
    IfEqual           <- Spacing "ifeq" Spacing "(" ArgExpression "," Spacing ArgExpression ")" endOfLine Statement+
    IfNotEqual        <- Spacing "ifneq" Spacing "(" ArgExpression "," Spacing ArgExpression ")" endOfLine Statement+
    Else              <- Spacing "else" endOfLine Statement+
    EndIf             <- Spacing  "endif" endOfLine
    SimpleStatement   <- Assignment / Include / Comment / Error / Override / Foo / Empty
    Assignment        <- Spacing VariableDecl Spacing (":=" / "=") Expression
    VariableDecl      <- identifier
    Expression        <- Function / NonEmptyString Variable / Variable / LiteralString
    ArgExpression     <- Function / Variable / ArgString
    ArgString         <- NonEmptyArgString / EmptyString
    NonEmptyArgString <- (!")" !"," .)+
    Function          <- Shell / FindString / IfFunc
    Shell             <- Spacing "$(shell " NonEmptyString ")"
    FindString        <- Spacing "$(findstring " ArgExpression "," ArgExpression ")"
    IfFunc            <- Spacing "$(if " ArgExpression "," ArgExpression "," ArgExpression ")"
    LiteralString     <- NonEmptyString / EmptyString
    NonEmptyString    <- [a-zA-Z_0-9./\- :]+
    EmptyString       <- ""
    Variable          <- "$(" (!")" .)* ")"
    Comment           <- Spacing "#" (!endOfLine .)*
    Include           <- "include" Spacing FileName
    FileName          <- FileNameChar*
    FileNameChar      <- [a-zA-Z_0-9./]
    Error             <- Spacing "$(error " Expression ")"
    Override          <- "override " VariableDecl ("=" / ":=") Expression
    Foo <- "foo " EmbeddedString
    EmbeddedString <- (FreeFormString? Variable?)*
    FreeFormString <- (!endOfLine !"$" .)*
    Empty             <- ""
`));
