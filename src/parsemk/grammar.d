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
    Variable           <- "$(" Name ")"
    Name               <- identifier
    Function           <- "$(" Name " " Expression ("," Expression)* ")"
    String             <- NonEmptyString / EmptyString
    NonEmptyString     <- (!"," !endOfLine !"$" !")" .)*
    EmptyString        <- ""
    Comment            <- Spacing "#" (!endOfLine .)*
    Include            <- "include" Spacing FileName
    Override           <- Spacing "override " Spacing Name ("=" / ":=") Spacing Expression
    FileName           <- FileNameChar*
    FileNameChar       <- [a-zA-Z_0-9./]
    Error <- ""
    Empty              <- ""


    # ArgString         <- NonEmptyArgString / EmptyString
    # NonEmptyArgString <- (!")" !"," .)+
    # Function          <- Shell / FindString / IfFunc / Subst / AddPrefix / AddSuffix
    # Shell             <- Spacing "$(shell " ArgString ")"
    # FindString        <- Spacing "$(findstring " Expression "," Expression ")"
    # IfFunc            <- Spacing "$(if " Expression "," Expression "," Expression ")"
    # LiteralString     <- NonEmptyString / EmptyString
    # NonEmptyString    <- [a-zA-Z_0-9./\- :]+
    # EmptyString       <- ""
    # Variable          <- "$(" (!")" .)* ")"
    # FileName          <- FileNameChar*
    # FileNameChar      <- [a-zA-Z_0-9./]
    # Error             <- Spacing "$(error " EmbeddedString
    # Override          <- "override " VariableDecl ("=" / ":=") EmbeddedString
    # EmbeddedString    <- (Function? Variable? FreeFormString?)*
    # FreeFormString    <- (!endOfLine !"$" .)*
    # Subst             <- Spacing "$(subst " Expression "," Expression "," Expression ")"
    # AddPrefix         <- Spacing "$(addprefix " Expression "," (SpaceArgExpression " "?)+ ")"
    # AddSuffix         <- Spacing "$(addsuffix " Expression "," (SpaceArgExpression " "?)+ ")"
    # SpaceArgExpression <- Function / Variable / SpaceArgString
    # SpaceArgString    <- (!")" !"," !" " .)+
`));
