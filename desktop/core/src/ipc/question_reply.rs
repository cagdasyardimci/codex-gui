use std::borrow::Cow;

use serde::Deserialize;

const OPEN: &str = "<send_user_message_question_reply>";
const CLOSE: &str = "</send_user_message_question_reply>";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Reply {
    question_item_id: String,
    question: String,
    answer: String,
}

pub fn present_question_reply(text: &str) -> Cow<'_, str> {
    let Some(payload) = text
        .trim()
        .strip_prefix(OPEN)
        .and_then(|value| value.strip_suffix(CLOSE))
    else {
        return Cow::Borrowed(text);
    };
    let Ok(replies) = serde_json::from_str::<Vec<Reply>>(payload) else {
        return Cow::Borrowed(text);
    };
    if replies.is_empty()
        || replies
            .iter()
            .any(|reply| reply.question_item_id.is_empty() || reply.question.trim().is_empty())
    {
        return Cow::Borrowed(text);
    }
    let rendered = replies
        .into_iter()
        .map(|reply| format!("{}\n{}", reply.question, reply.answer))
        .collect::<Vec<_>>()
        .join("\n\n");
    Cow::Owned(rendered)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_complete_valid_envelopes_replace_the_literal_text() {
        let text = format!(
            "{OPEN}[{{\"questionItemId\":\"one\",\"question\":\"Which area?\",\"answer\":\"Chat\"}},\
            {{\"questionItemId\":\"two\",\"question\":\"What changed?\",\"answer\":\"Typing\\nSelection\"}}]{CLOSE}"
        );
        assert_eq!(
            present_question_reply(&text),
            "Which area?\nChat\n\nWhat changed?\nTyping\nSelection"
        );
        for literal in [
            format!("Explain:\n{text}"),
            format!("```\n{text}\n```"),
            format!("{text}\nTrailing prose"),
            text.trim_end_matches(CLOSE).into(),
            format!("{OPEN}[]{CLOSE}"),
            format!(
                "{OPEN}[{{\"questionItemId\":\"valid\",\"question\":\"Any?\",\"answer\":3}}]{CLOSE}"
            ),
        ] {
            assert_eq!(present_question_reply(&literal), literal);
        }
    }
}
