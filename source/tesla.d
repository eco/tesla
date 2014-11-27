import diggler.bot;
import irc.protocol;
import std.regex;
import std.net.curl;
import std.algorithm;
import std.range;
import std.array;
import std.conv;
import std.stdio;
import std.encoding;
import std.datetime;
import std.exception;
import std.string;
import std.typecons;

import entities;

@category("echobot")
class EchoCommands : CommandSet!EchoCommands
{
    mixin CommandContext!();

    @usage("repeat the given text.")
    void echo(in char[] text)
    {
        reply("%s: %s", user.nickName, text);
    }
}

struct Note
{
    string author;
    string message;
    SysTime time;
}

@category("notes")
class NoteCommands : CommandSet!NoteCommands
{
    mixin CommandContext!();

    Note[][string] notes;

    @usage("leaves a note for someone")
    void note(in char[] text)
    {
        static note_re = ctRegex!(r"(\S+?)\s+(.+)");

        auto m = matchFirst(text, note_re);

        if (!m.hit)
        {
            reply("%s: syntax is '<nick> <note...>'", user.nickName);
            return;
        }

        auto addressee = m.captures[1];
        auto note = m.captures[2];
        notes[addressee] ~= Note(user.nickName.dup, note.dup, Clock.currTime());

        reply("%s: %s will be notified when they talk or join", user.nickName, addressee);
    }


    void dispatchPendingNotes(string user)
    {
        if (auto user_notes = user in notes)
        {
            foreach(note; *user_notes)
            {
                reply("%s: %s left a note for you %s ago:", user, note.author, Clock.currTime() - note.time);
                reply("%s: <%s> %s", user, note.author, note.message);
            }
            notes.remove(user);
        }
    }
}

@category("hail")
class HailCommands : CommandSet!HailCommands
{
    mixin CommandContext!();

    @usage("gets everyones attention")
    void hail()
    {
        reply("%s: %s is being super needy right now",
              channel.users.map!(a => a.nickName).joiner(", "),
              user.nickName);
    }
}

string[] scrapeTitles(M)(in M message)
{
    static re_url = ctRegex!(r"(https?|ftp)://[^\s/$.?#].[^\s]*", "i");
    static re_title = ctRegex!(r"<title.*?>(.*?)<", "si");
    static re_ws = ctRegex!(r"(\s{2,}|\n|\t)");

    return matchAll(message, re_url)
              .map!(      match => match.captures[0] )
              .map!(        url => get(url, limitRange("0-4096")).ifThrown([]) ) // just first 4k
              .map!(    content => matchFirst(cast(char[])content, re_title) )
              .array // cache to prevent multiple evaluations of preceding
              .filter!( capture => !capture.empty )
              .map!(    capture => capture[1].idup.entitiesToUni )
              .map!(  uni_title => uni_title.replaceAll(re_ws, " ") )
              .array
              .ifThrown(string[].init); // [] should work, possible bug
}

auto limitRange(string range)
{
    import etc.c.curl : CurlOption;
    auto http = HTTP();
    http.handle.set(CurlOption.range, range);

    return http;
}

