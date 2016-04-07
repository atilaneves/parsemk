module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Statements         <- Statement*
    Statement          <- CompoundStatement / SimpleStatement endOfLine
    CompoundStatement  <- ConditionBlock
    ConditionBlock     <- (IfEqual / IfNotEqual) Else? EndIf
    IfEqual            <- Spacing "ifeq" Spacing "(" Expression "," Spacing Expression ")" endOfLine Statement+
    IfNotEqual         <- Spacing "ifneq" Spacing "(" Expression "," Spacing Expression ")" endOfLine Statement+
    Else               <- Spacing "else" endOfLine Statement+
    EndIf              <- Spacing  "endif" endOfLine
    SimpleStatement    <- Override / Assignment / PlusEqual / Include / Comment / Error / Empty
    Assignment         <- Spacing Name Spacing (":=" / "=") Expression
    PlusEqual          <- Spacing Name Spacing "+=" Spacing Expression
    Expression         <- (Function? Variable? String?)+
    Variable           <- NormalVariable / IndexVariable
    NormalVariable     <- "$(" Expression ")" / "$(" Name ")" / "$" Name
    IndexVariable      <- "$" digit
    Name               <- identifier
    Function           <- "$(" Name " " Expression ("," Expression)* ")"
    String             <- Quoted / NiceString
    Quoted             <- "'" (!"'" .)* "'"
    NiceString         <- (!"," !endOfLine !"$" !")" !"'" .)*
    Comment            <- Spacing "#" (!endOfLine .)*
    Include            <- "include" Spacing FileName
    Override           <- Spacing "override " Spacing Name ("=" / ":=") Spacing Expression
    FileName           <- FileNameChar*
    FileNameChar       <- [a-zA-Z_0-9./]
    Error              <- Spacing "$(error " ErrorExpression ")"
    ErrorExpression    <- (Function? Variable? ErrorString?)+
    ErrorString        <- (!endOfLine !"$" !")" .)*
    Empty              <- ""
`));
