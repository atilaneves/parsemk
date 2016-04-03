module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Lines      <- Line*
    Line       <- Ignore / Assignment
    Assignment <- Variable ":=" identifier endOfLine
    Variable   <- identifier
    Ignore     <- Comment / Empty
    Comment    <- Spacing "#" (!endOfLine .)* endOfLine
    Empty      <- endOfLine / Spacing endOfLine
`));
