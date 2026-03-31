# Wreck

a language with the goal of making you ask:
> what exactly separates a scripting language from a programming language?

this project is 100% human written, clanker free code

>[!WARNING]
>this is still super early development, so it can't do much (***yet***),
> also, expect breaking changes

---

(I do have a standard library planned, but I need to do a lot of work before I can start working on that)

(current) features:
- just like a Shell scriping language, it can run shell commands
  - running a shell command is called just like calling any other function
- flags as a datatype
- interpreted

current state of the syntax (for example)
```wreck
yt-dlp([ o ] "%(title)s" [ x audio-format ] mp3 [ embed-thumbnail embed-metadata ] "https://some.url.and_tld");
```

---

I currently plan to make the syntax something like this (for example) (not everything here is implmented ***yet***)

```wreck
//declare the package name and file setup
pkg primary (
    //imports
    [[ needed_pkgs ]] {
        foo = "insert some repo url here"
    }
    //I'll probably have more options here
);

//'set' is equivalent to 'const'
set version = "1.0.0";

//'let' is equivalent to 'var'
//  (also, an anonymous enum can be used)
//    ('._type' refers to the type of the enum, similar to Zig's @TypeOf() builtin)
let mode = enum { NORMAL SELECT }.NORMAL;

//the program entry-point
//  (flag is a datatype similar to a string, but it has some extra stuff)
fn main(args []flag) bool {
    //an if statement
    ? (args.len < 1) {
        //flags can be passed to functions similar to a shell command,
        //  also, '@' is used to call functions from other packages
        //    the standard library is imported by default
        //      (this can be disabled in the file setup)
        @std.printf[[ err ]]("not enough args\n");
        return false; //returning 'false' indicates a failure
    }

    //flags (and strings, and lists) have a built-in iterator
    //  the iterator has a function to switch on each value
    args.itr.switchEach({
        //when iterating over a flag, it's coerced into a string 
        "version" "v" {
            @std.printf("version {s}\n" version);
        }
        "select" "s" {
            mode = .SELECT;
            @std.printf("using select mode\n");
        }
        else {
            //similar to Zig, the printf-like format syntax uses braces
            //  (the 'q' format automatically quotes and escapes the string)
            @std.printf[[ err ]](
                "invalid argument: {q} (number: {d})"
                args.itr.current args.itr.pos
            );
        }
    });

    //pipes can be used as a form of a buffer
    let filename = @std.pipe;

    //if a function is not manually defined (or overridden),
    //  it defaults to running a shell command,
    //    this can be disabled in the file setup
    date[[ filename ]]("+%y%_m%_d_%H%M%S");

    @std.printf("output filename: {s}" filename.contents);

    //lists don't require commas, they're needless if the tokenizer already
    //  knows when a value ends and whitespace starts (so whitespace is a separator)
    set paths = [
        @std.os.get_usr_dir()
        "Pictures"
        "Screenshots"
        filename.contents
    ];

    //lists also have iterators, and 'doEach' is similar to 'forEach'
    paths.itr.doEach(
        //iterators also have a built-in memory that can be used for
        //  cancatenations, for example
        @std.path.join([[ file ]] paths.itr.mem paths.itr.current)
    );

    //in this example, the iterator's memory holds the final value
    set filepath = paths.itr.mem;
    
    //a switch can also be used to directly set a value 
    let mode_str = switch (mode) {
        .SELECT { "region" }
        .NORMAL { "active" }
    }
    
    //flags can be passed to shell commands using the []flag datatype
    //  by default, single-character flags are converted to (for example) '-m'
    //    and multi-letter flags are converted to (for example) '--foo',
    //      you can flip this behavior for a specific flag by *[syntax TBD]* 
    hyprshot(
        [[ m ]] mode_str
        [[ o ]] @std.path.base(paths.itr.mem)
        [[ f ]] filename.contents
    //if a function call (or shell command) fails, you can handle
    //  it manually, or by default let the interpreter panic if unhandled,
    //    you can disable the panic or define a custom function to handle it
    //      in the file setup
    ) onerr |error| {
        @std.printf[[ err ]](
            "failed to take a screenshot (exit code: {d}): {s}"
            error.code error.stderr.contents // the error contains values
        );
        return false;
    }

    @std.printf("took a screenshot ({s})\n" paths.mem);

    return true; //ok; 'false' means not-ok
}
```
