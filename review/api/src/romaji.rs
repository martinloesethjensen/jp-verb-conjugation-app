//! Typed romaji to hiragana, so a Latin-letter search finds Japanese text. A port of VerbKit's
//! `Romaji.toHiragana` (Hepburn and Nihon-shiki, one table), with one addition: `m` before `b`, `p` or
//! `m` is ん (shimbun). Text that isn't romaji (kana, kanji, spaces) passes through unchanged; a
//! half-typed ending ("tab", "tabesh") is dropped so results narrow as the user types.

const MAX_KEY: usize = 4;

/// `romaji:kana` pairs; one table for every accepted spelling.
const SPEC: &str = "
a:あ i:い u:う e:え o:お
ka:か ki:き ku:く ke:け ko:こ kya:きゃ kyu:きゅ kyo:きょ
ga:が gi:ぎ gu:ぐ ge:げ go:ご gya:ぎゃ gyu:ぎゅ gyo:ぎょ
sa:さ shi:し si:し su:す se:せ so:そ sha:しゃ shu:しゅ sho:しょ she:しぇ sya:しゃ syu:しゅ syo:しょ
za:ざ ji:じ zi:じ zu:ず ze:ぜ zo:ぞ ja:じゃ ju:じゅ jo:じょ je:じぇ
jya:じゃ jyu:じゅ jyo:じょ zya:じゃ zyu:じゅ zyo:じょ
ta:た chi:ち ti:ち tsu:つ tu:つ te:て to:と cha:ちゃ chu:ちゅ cho:ちょ che:ちぇ
tya:ちゃ tyu:ちゅ tyo:ちょ cya:ちゃ cyu:ちゅ cyo:ちょ
da:だ di:ぢ du:づ dzu:づ de:で do:ど dya:ぢゃ dyu:ぢゅ dyo:ぢょ
na:な ni:に nu:ぬ ne:ね no:の nya:にゃ nyu:にゅ nyo:にょ
ha:は hi:ひ fu:ふ hu:ふ he:へ ho:ほ hya:ひゃ hyu:ひゅ hyo:ひょ fa:ふぁ fi:ふぃ fe:ふぇ fo:ふぉ
ba:ば bi:び bu:ぶ be:べ bo:ぼ bya:びゃ byu:びゅ byo:びょ
pa:ぱ pi:ぴ pu:ぷ pe:ぺ po:ぽ pya:ぴゃ pyu:ぴゅ pyo:ぴょ
ma:ま mi:み mu:む me:め mo:も mya:みゃ myu:みゅ myo:みょ
ya:や yu:ゆ yo:よ
ra:ら ri:り ru:る re:れ ro:ろ rya:りゃ ryu:りゅ ryo:りょ
wa:わ wo:を
xa:ぁ xi:ぃ xu:ぅ xe:ぇ xo:ぉ la:ぁ li:ぃ lu:ぅ le:ぇ lo:ぉ
xya:ゃ xyu:ゅ xyo:ょ lya:ゃ lyu:ゅ lyo:ょ
xtu:っ ltu:っ xtsu:っ ltsu:っ
";

fn lookup(key: &str) -> Option<&'static str> {
    SPEC.split_whitespace()
        .filter_map(|pair| pair.split_once(':'))
        .find(|(romaji, _)| *romaji == key)
        .map(|(_, kana)| kana)
}

fn is_prefix_of_a_key(rest: &str) -> bool {
    SPEC.split_whitespace()
        .filter_map(|pair| pair.split_once(':'))
        .any(|(romaji, _)| romaji.starts_with(rest))
}

fn normalized(text: &str) -> Vec<char> {
    let mut out = String::new();
    for c in text.to_lowercase().chars() {
        match c {
            'ā' => out.push_str("aa"),
            'ī' => out.push_str("ii"),
            'ū' => out.push_str("uu"),
            'ē' => out.push_str("ee"),
            'ō' => out.push_str("ou"),
            other => out.push(other),
        }
    }
    out.chars().collect()
}

fn vowel_or_y(c: char) -> bool {
    "aiueoy".contains(c)
}

/// `None` when the text has no Latin letter or nothing converts.
pub fn to_hiragana(text: &str) -> Option<String> {
    let chars = normalized(text);
    let at = |i: usize| chars.get(i).copied();
    let mut out = String::new();
    let (mut saw_latin, mut converted) = (false, false);
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if !c.is_ascii_alphabetic() {
            out.push(c);
            i += 1;
            continue;
        }
        saw_latin = true;
        let next = at(i + 1);
        if c == 'n' {
            match next {
                None => {
                    out.push('ん');
                    converted = true;
                    i += 1;
                    continue;
                }
                Some('\'') => {
                    out.push('ん');
                    converted = true;
                    i += 2;
                    continue;
                }
                Some('n') => {
                    out.push('ん');
                    converted = true;
                    i += if at(i + 2).is_some_and(vowel_or_y) {
                        1
                    } else {
                        2
                    };
                    continue;
                }
                Some(n) if !vowel_or_y(n) => {
                    out.push('ん');
                    converted = true;
                    i += 1;
                    continue;
                }
                _ => {}
            }
        }
        if c == 'm' && matches!(next, Some('b' | 'p' | 'm')) {
            out.push('ん');
            converted = true;
            i += 1;
            continue;
        }
        if next == Some(c) && !"aiueon".contains(c) {
            out.push('っ');
            converted = true;
            i += 1;
            continue;
        }
        if c == 't' && at(i + 1) == Some('c') && at(i + 2) == Some('h') {
            out.push('っ');
            converted = true;
            i += 1;
            continue;
        }
        let mut matched = false;
        for length in (1..=MAX_KEY.min(chars.len() - i)).rev() {
            let key: String = chars[i..i + length].iter().collect();
            if let Some(kana) = lookup(&key) {
                out.push_str(kana);
                converted = true;
                i += length;
                matched = true;
                break;
            }
        }
        if matched {
            continue;
        }
        let rest: String = chars[i..].iter().collect();
        if is_prefix_of_a_key(&rest) {
            break; // a half-typed ending
        }
        return None;
    }
    (saw_latin && converted).then_some(out)
}
