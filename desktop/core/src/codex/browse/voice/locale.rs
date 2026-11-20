use crate::ipc::VoiceChoice;

const ENGLISH_SAMPLE: &str = "Hello! Here’s a short sample of this voice.";
type VoiceLanguage = (&'static str, &'static [&'static str], &'static str);
const LANGUAGES: &[VoiceLanguage] = &[
    (
        "American English",
        &[
            "bubbie", "juniper", "spruce", "maple", "sol", "breeze", "cove", "ember",
        ],
        ENGLISH_SAMPLE,
    ),
    (
        "Brazilian Portuguese",
        &["rio", "viola"],
        "Olá! Aqui vai uma pequena amostra desta voz.",
    ),
    ("British English", &["arbor", "vale"], ENGLISH_SAMPLE),
    (
        "French",
        &["rivage", "aube"],
        "Bonjour ! Voici un court extrait de cette voix.",
    ),
    (
        "German",
        &["miko", "sonna"],
        "Hallo! Hier ist eine kurze Hörprobe dieser Stimme.",
    ),
    (
        "Hindi",
        &["neer", "leher"],
        "नमस्ते! यह इस आवाज़ की एक छोटी सी झलक है।",
    ),
    (
        "Japanese",
        &["rindo", "himari"],
        "こんにちは。この声の短いサンプルをお聞きください。",
    ),
    (
        "Korean",
        &["hanul", "haetsal"],
        "안녕하세요! 이 목소리의 짧은 예시를 들려드릴게요.",
    ),
    (
        "Mexican Spanish",
        &["tinta"],
        "¡Hola! Aquí tienes una breve muestra de esta voz.",
    ),
];

fn language(voice: &str) -> Option<&'static VoiceLanguage> {
    LANGUAGES.iter().find(|(_, ids, _)| ids.contains(&voice))
}

pub(super) fn choice(voice: String) -> VoiceChoice {
    let label = if voice == "rindo" {
        "Rindō".into()
    } else {
        let mut characters = voice.chars();
        characters
            .next()
            .into_iter()
            .flat_map(char::to_uppercase)
            .chain(characters)
            .collect()
    };
    VoiceChoice {
        language: language(&voice).map(|(label, _, _)| (*label).to_owned()),
        id: voice,
        label,
    }
}

pub fn voice_sample(voice: &str) -> &'static str {
    language(voice).map_or(ENGLISH_SAMPLE, |(_, _, sample)| sample)
}
