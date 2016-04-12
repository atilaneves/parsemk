module parsemk.io;


string sanitize(in string input) {
    import std.string;

    return input
        .replace("\\\n", "")
        .replace("$$", "$")
        ;
}
