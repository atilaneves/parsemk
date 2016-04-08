module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Statements         <- Statement*
    Statement          <- SimpleStatement endOfLine / CompoundStatement
    CompoundStatement  <- ConditionBlock / TargetBlock
    TargetBlock        <- Outputs ":" " "* Inputs endOfLine (CommandLine)*
    #Outputs            <- (!":" !endOfLine .)*
    Outputs            <- Expression
    Inputs             <- Expression
    CommandLine        <- "\t" "@"? Expression endOfLine
    ConditionBlock     <- (IfEqual / IfNotEqual) Else? EndIf
    IfEqual            <- Spacing "ifeq" Spacing "(" Expression "," Spacing Expression ")" endOfLine Statement+
    IfNotEqual         <- Spacing "ifneq" Spacing "(" Expression "," Spacing Expression ")" endOfLine Statement+
    Else               <- Spacing "else" endOfLine Statement+
    EndIf              <- Spacing  "endif" endOfLine
    SimpleStatement    <- Override / Assignment / PlusEqual / Include / Comment / Error / Empty
    Assignment         <- Spacing Name Spacing (":=" / "=") Expression?
    PlusEqual          <- Spacing Name Spacing "+=" Spacing Expression
    Expression         <- (Function? Variable? String?)+
    Variable           <- NormalVariable / IndexVariable / ForEachVariable
    NormalVariable     <- "$(" Expression ")" / "$(" Name ")" / "$@"
    IndexVariable      <- "$" digit
    ForEachVariable    <- "$" identifier
    Name               <- identifier
    Function           <- "$(" Name (" " / "\t")+ Expression ("," Expression)* ")"
    String             <- Quoted / NiceString
    Quoted             <- "'" (!"'" .)* "'"
    NiceString         <- (!"," !endOfLine !"$" !")" !"'" !":" .)*
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
