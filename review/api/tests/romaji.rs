use review_api::romaji::to_hiragana;

fn kana(text: &str) -> Option<String> {
    to_hiragana(text)
}

fn is(text: &str, expected: &str) {
    assert_eq!(kana(text).as_deref(), Some(expected), "{text}");
}

#[test]
fn basic_words() {
    is("taberu", "たべる");
    is("tabemashita", "たべました");
    is("kyou", "きょう");
    is("nomu", "のむ");
}

#[test]
fn hepburn_and_nihon_shiki_variants() {
    for (romaji, expected) in [
        ("shi", "し"),
        ("si", "し"),
        ("chi", "ち"),
        ("ti", "ち"),
        ("tsu", "つ"),
        ("tu", "つ"),
        ("fu", "ふ"),
        ("hu", "ふ"),
        ("ja", "じゃ"),
        ("zya", "じゃ"),
        ("jya", "じゃ"),
        ("sha", "しゃ"),
        ("cho", "ちょ"),
        ("kyu", "きゅ"),
        ("wo", "を"),
    ] {
        is(romaji, expected);
    }
}

#[test]
fn long_vowels_and_macrons() {
    is("ou", "おう");
    is("oo", "おお");
    is("kyō", "きょう");
    is("ī", "いい");
}

#[test]
fn doubled_consonants() {
    is("kka", "っか");
    is("kitte", "きって");
    is("zasshi", "ざっし");
    is("matchi", "まっち");
    is("ippai", "いっぱい");
}

#[test]
fn n_rules() {
    is("kan", "かん");
    is("kanji", "かんじ");
    is("kanna", "かんな");
    is("konnichiwa", "こんにちわ");
    is("kin'en", "きんえん");
    is("n'a", "んあ");
    is("na", "な");
    is("shinbun", "しんぶん");
    is("shimbun", "しんぶん");
    is("annai", "あんない");
}

#[test]
fn case_and_partial_endings() {
    is("TaBeRu", "たべる");
    is("tab", "た");
    is("tabesh", "たべ");
}

#[test]
fn not_romaji_gives_none() {
    for text in ["", "   ", "たべる", "食べる", "k", "sh", "qux", "tabeqru"] {
        assert_eq!(kana(text), None, "{text:?}");
    }
}

#[test]
fn mixed_kana_passes_through() {
    is("食beru", "食べる");
}
