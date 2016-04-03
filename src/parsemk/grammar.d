module parsemk.grammar;

import pegged.grammar;

mixin(pegged.grammar.grammar(`
Makefile:
    Lines        <- Line*
    Line         <- Assignment / Include / Ignore
    Assignment   <- Variable ":=" identifier? endOfLine
    Variable     <- identifier
    Include      <- "include" Spacing FileName endOfLine
    FileName     <- FileNameChar*
    FileNameChar <- [a-zA-Z_0-9./]
    Ignore       <- Comment / Empty
    Comment      <- Spacing "#" (!endOfLine .)* endOfLine
    Empty        <- endOfLine / Spacing endOfLine
`));
