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
