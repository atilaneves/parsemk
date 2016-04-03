import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Lines      <- Line*
    Line       <- Empty / Assignment
    Assignment <- Variable ":=" identifier
    Variable   <- identifier
    Empty      <- "\n" / "\r\n" / Comment
    Comment    <- Spacing "#" Spacing .*
`));
