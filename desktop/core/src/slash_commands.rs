use serde::{Deserialize, Serialize};
use ts_rs::TS;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize, TS)]
#[serde(rename_all = "lowercase")]
#[ts(rename = "SlashCommand")]
pub enum Command {
    New,
    Resume,
    Fork,
    Rename,
    Archive,
    Delete,
    Compact,
    Review,
    Model,
    Reasoning,
    Fast,
    Permissions,
    Plan,
    Status,
    Skills,
    Mention,
    Diff,
    Copy,
}

#[derive(Clone, Copy)]
enum Arguments {
    None,
    Identifier,
    Text,
    Choice(&'static [&'static str]),
    ReviewTarget,
}

pub struct CommandSpec {
    pub command: Command,
    pub name: &'static str,
    pub placeholder: Option<&'static str>,
    arguments: Arguments,
}

const fn spec(
    command: Command,
    name: &'static str,
    placeholder: Option<&'static str>,
    arguments: Arguments,
) -> CommandSpec {
    CommandSpec {
        command,
        name,
        placeholder,
        arguments,
    }
}

pub const COMMANDS: &[CommandSpec] = &[
    spec(Command::New, "new", None, Arguments::None),
    spec(
        Command::Resume,
        "resume",
        Some("thread-id"),
        Arguments::Identifier,
    ),
    spec(Command::Fork, "fork", None, Arguments::None),
    spec(Command::Rename, "rename", Some("name"), Arguments::Text),
    spec(Command::Archive, "archive", None, Arguments::None),
    spec(Command::Delete, "delete", None, Arguments::None),
    spec(Command::Compact, "compact", None, Arguments::None),
    spec(
        Command::Review,
        "review",
        Some("uncommitted|base <branch>|commit <sha>|custom <instructions>"),
        Arguments::ReviewTarget,
    ),
    spec(
        Command::Model,
        "model",
        Some("model-id"),
        Arguments::Identifier,
    ),
    spec(
        Command::Reasoning,
        "reasoning",
        Some("effort"),
        Arguments::Identifier,
    ),
    spec(
        Command::Fast,
        "fast",
        Some("on|off"),
        Arguments::Choice(&["on", "off"]),
    ),
    spec(
        Command::Permissions,
        "permissions",
        Some("ask|auto|full"),
        Arguments::Choice(&["ask", "auto", "full"]),
    ),
    spec(Command::Plan, "plan", Some("prompt"), Arguments::Text),
    spec(Command::Status, "status", None, Arguments::None),
    spec(Command::Skills, "skills", None, Arguments::None),
    spec(Command::Mention, "mention", None, Arguments::None),
    spec(Command::Diff, "diff", None, Arguments::None),
    spec(Command::Copy, "copy", None, Arguments::None),
];

const ROOT_DIRECTORIES: &[&str] = &[
    "Applications",
    "Library",
    "System",
    "Users",
    "Volumes",
    "bin",
    "cores",
    "dev",
    "etc",
    "home",
    "mnt",
    "opt",
    "private",
    "sbin",
    "tmp",
    "usr",
    "var",
];

#[derive(Debug, PartialEq)]
pub enum ComposerInput<'a> {
    Text,
    Literal(String),
    Command {
        command: Command,
        arguments: &'a str,
    },
    Invalid,
}

pub fn parse(draft: &str) -> ComposerInput<'_> {
    let left = draft.trim_start_matches([' ', '\t']);
    let Some(after_slash) = left.strip_prefix('/') else {
        return ComposerInput::Text;
    };
    let (literal, remaining) = match after_slash.strip_prefix('/') {
        Some(remaining) => (true, remaining),
        None => (false, after_slash),
    };
    let end = remaining
        .find(char::is_whitespace)
        .unwrap_or(remaining.len());
    let name = &remaining[..end];
    if !command_name(name) {
        return ComposerInput::Text;
    }
    if literal {
        let leading = draft.len() - left.len();
        return ComposerInput::Literal(format!("{}{}", &draft[..leading], after_slash));
    }
    let Some(spec) = COMMANDS
        .iter()
        .find(|spec| spec.name.eq_ignore_ascii_case(name))
    else {
        return if ROOT_DIRECTORIES.contains(&name) {
            ComposerInput::Text
        } else {
            ComposerInput::Invalid
        };
    };
    let separator = &remaining[end..];
    let arguments = if let Some(after_pair) = separator.strip_prefix("\r\n") {
        after_pair
    } else {
        separator
            .chars()
            .next()
            .map_or("", |space| &separator[space.len_utf8()..])
    };
    if !accepts(spec.arguments, arguments.trim()) {
        return ComposerInput::Invalid;
    }
    ComposerInput::Command {
        command: spec.command,
        arguments,
    }
}

fn command_name(name: &str) -> bool {
    name.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
}

fn accepts(kind: Arguments, value: &str) -> bool {
    match kind {
        Arguments::None => value.is_empty(),
        Arguments::Identifier => !value.contains(char::is_whitespace),
        Arguments::Text => true,
        Arguments::Choice(choices) => value.is_empty() || choices.contains(&value),
        Arguments::ReviewTarget => {
            if value.is_empty() || value == "uncommitted" {
                return true;
            }
            let Some((kind, value)) = value.split_once(char::is_whitespace) else {
                return false;
            };
            let value = value.trim_start();
            !value.is_empty()
                && match kind {
                    "base" | "commit" => !value.contains(char::is_whitespace),
                    "custom" => true,
                    _ => false,
                }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{Command, ComposerInput, parse};

    #[test]
    fn leading_command_syntax_preserves_text_and_does_not_treat_paths_as_commands() {
        assert_eq!(
            parse(" \t//status café\n  next"),
            ComposerInput::Literal(" \t/status café\n  next".into())
        );
        for text in [
            "./review",
            "/Users/me",
            "/tmp",
            "//server/share",
            "/éclair",
            "\n/plan",
            "Fix /plan",
        ] {
            assert_eq!(parse(text), ComposerInput::Text, "{text:?}");
        }
        assert_eq!(
            parse(" \t/PLAN\r\n  café\n\nnext "),
            ComposerInput::Command {
                command: Command::Plan,
                arguments: "  café\n\nnext ",
            }
        );
        assert_eq!(parse("/misspelled"), ComposerInput::Invalid);
    }

    #[test]
    fn arguments_follow_the_command_registry() {
        for text in [
            "/archive  bye",
            "/resume two IDs",
            "/review base",
            "/review commit a b",
            "/review custom ",
            "/fast maybe",
            "/permissions FULL",
        ] {
            assert_eq!(parse(text), ComposerInput::Invalid, "{text}");
        }
        for (text, command) in [
            ("/new", Command::New),
            ("/model model-2", Command::Model),
            ("/rename A new name", Command::Rename),
            ("/fast on", Command::Fast),
            ("/review custom review the staged changes", Command::Review),
            ("/review base feature/branch", Command::Review),
            ("/review uncommitted", Command::Review),
            ("/permissions full ", Command::Permissions),
        ] {
            assert!(
                matches!(parse(text), ComposerInput::Command { command: parsed, .. } if command == parsed),
                "{text}"
            );
        }
    }
}
