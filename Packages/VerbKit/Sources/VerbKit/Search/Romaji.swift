import Foundation

/// Converts typed romaji to hiragana so Latin-letter queries can find Japanese text.
/// Accepts Hepburn and Nihon-shiki spellings. Text that is not romaji (kana, kanji,
/// spaces) passes through unchanged. A half-typed ending ("tab", "tabesh") is dropped
/// rather than rejected, so results narrow as the user types.
public enum Romaji {
    /// nil when the text has no Latin letter or nothing converts.
    public static func toHiragana(_ text: String) -> String? {
        let chars = Array(normalized(text))
        var output = ""
        var sawLatin = false
        var convertedAny = false
        var i = 0

        while i < chars.count {
            let c = chars[i]
            guard isLatinLetter(c) else {
                output.append(c)
                i += 1
                continue
            }
            sawLatin = true
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if c == "n" {
                if next == nil {
                    output += "ん"; convertedAny = true; i += 1; continue
                }
                if next == "'" {
                    output += "ん"; convertedAny = true; i += 2; continue
                }
                if next == "n" {
                    let after: Character? = i + 2 < chars.count ? chars[i + 2] : nil
                    output += "ん"; convertedAny = true
                    if let after, isVowelOrY(after) { i += 1 } else { i += 2 }
                    continue
                }
                if let next, !isVowelOrY(next) {
                    output += "ん"; convertedAny = true; i += 1; continue
                }
            }

            if let next, next == c, !"aiueon".contains(c) {
                output += "っ"; convertedAny = true; i += 1; continue
            }
            if c == "t", i + 2 < chars.count, chars[i + 1] == "c", chars[i + 2] == "h" {
                output += "っ"; convertedAny = true; i += 1; continue
            }

            var matched = false
            var length = min(maxKeyLength, chars.count - i)
            while length >= 1 {
                if let kana = table[String(chars[i..<i + length])] {
                    output += kana; convertedAny = true; i += length; matched = true
                    break
                }
                length -= 1
            }
            if matched { continue }

            let rest = String(chars[i...])
            if table.keys.contains(where: { $0.hasPrefix(rest) }) { break }   // half-typed ending
            return nil
        }
        return sawLatin && convertedAny ? output : nil
    }

    private static func normalized(_ text: String) -> String {
        var result = text.lowercased()
        for (macron, plain) in [("ā", "aa"), ("ī", "ii"), ("ū", "uu"), ("ē", "ee"), ("ō", "ou")] {
            result = result.replacingOccurrences(of: macron, with: plain)
        }
        return result
    }

    private static func isLatinLetter(_ c: Character) -> Bool {
        c.isASCII && c.isLetter
    }

    private static func isVowelOrY(_ c: Character) -> Bool {
        "aiueoy".contains(c)
    }

    private static let maxKeyLength = 4

    /// romaji:kana pairs; one table for every accepted spelling.
    private static let table: [String: String] = {
        let spec = """
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
        """
        var result: [String: String] = [:]
        for pair in spec.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let parts = pair.split(separator: ":")
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }()
}
