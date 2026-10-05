/// The eight regions dialect tags are grouped by. Uses the common eight-region
/// split, in which 三重県 belongs to 関西 (近畿).
public enum Region: String, Codable, CaseIterable, Sendable {
    case hokkaido, tohoku, kanto, chubu, kansai, chugoku, shikoku, kyushuOkinawa

    public var name: String {
        switch self {
        case .hokkaido: return "北海道"
        case .tohoku: return "東北"
        case .kanto: return "関東"
        case .chubu: return "中部"
        case .kansai: return "関西"
        case .chugoku: return "中国"
        case .shikoku: return "四国"
        case .kyushuOkinawa: return "九州・沖縄"
        }
    }

    public var romaji: String {
        switch self {
        case .hokkaido: return "Hokkaido"
        case .tohoku: return "Tohoku"
        case .kanto: return "Kanto"
        case .chubu: return "Chubu"
        case .kansai: return "Kansai"
        case .chugoku: return "Chugoku"
        case .shikoku: return "Shikoku"
        case .kyushuOkinawa: return "Kyushu-Okinawa"
        }
    }

    /// The region's prefectures, in JIS order.
    public var prefectures: [Prefecture] {
        Prefecture.allCases.filter { $0.region == self }
    }
}

/// The 47 prefectures in JIS code order (北海道 is 1, 沖縄県 is 47).
public enum Prefecture: String, Codable, CaseIterable, Sendable {
    case hokkaido
    case aomori, iwate, miyagi, akita, yamagata, fukushima
    case ibaraki, tochigi, gunma, saitama, chiba, tokyo, kanagawa
    case niigata, toyama, ishikawa, fukui, yamanashi, nagano, gifu, shizuoka, aichi
    case mie, shiga, kyoto, osaka, hyogo, nara, wakayama
    case tottori, shimane, okayama, hiroshima, yamaguchi
    case tokushima, kagawa, ehime, kochi
    case fukuoka, saga, nagasaki, kumamoto, oita, miyazaki, kagoshima, okinawa

    private var info: (name: String, kana: String, romaji: String, region: Region) {
        switch self {
        case .hokkaido: return ("北海道", "ほっかいどう", "Hokkaido", .hokkaido)
        case .aomori: return ("青森県", "あおもりけん", "Aomori", .tohoku)
        case .iwate: return ("岩手県", "いわてけん", "Iwate", .tohoku)
        case .miyagi: return ("宮城県", "みやぎけん", "Miyagi", .tohoku)
        case .akita: return ("秋田県", "あきたけん", "Akita", .tohoku)
        case .yamagata: return ("山形県", "やまがたけん", "Yamagata", .tohoku)
        case .fukushima: return ("福島県", "ふくしまけん", "Fukushima", .tohoku)
        case .ibaraki: return ("茨城県", "いばらきけん", "Ibaraki", .kanto)
        case .tochigi: return ("栃木県", "とちぎけん", "Tochigi", .kanto)
        case .gunma: return ("群馬県", "ぐんまけん", "Gunma", .kanto)
        case .saitama: return ("埼玉県", "さいたまけん", "Saitama", .kanto)
        case .chiba: return ("千葉県", "ちばけん", "Chiba", .kanto)
        case .tokyo: return ("東京都", "とうきょうと", "Tokyo", .kanto)
        case .kanagawa: return ("神奈川県", "かながわけん", "Kanagawa", .kanto)
        case .niigata: return ("新潟県", "にいがたけん", "Niigata", .chubu)
        case .toyama: return ("富山県", "とやまけん", "Toyama", .chubu)
        case .ishikawa: return ("石川県", "いしかわけん", "Ishikawa", .chubu)
        case .fukui: return ("福井県", "ふくいけん", "Fukui", .chubu)
        case .yamanashi: return ("山梨県", "やまなしけん", "Yamanashi", .chubu)
        case .nagano: return ("長野県", "ながのけん", "Nagano", .chubu)
        case .gifu: return ("岐阜県", "ぎふけん", "Gifu", .chubu)
        case .shizuoka: return ("静岡県", "しずおかけん", "Shizuoka", .chubu)
        case .aichi: return ("愛知県", "あいちけん", "Aichi", .chubu)
        case .mie: return ("三重県", "みえけん", "Mie", .kansai)
        case .shiga: return ("滋賀県", "しがけん", "Shiga", .kansai)
        case .kyoto: return ("京都府", "きょうとふ", "Kyoto", .kansai)
        case .osaka: return ("大阪府", "おおさかふ", "Osaka", .kansai)
        case .hyogo: return ("兵庫県", "ひょうごけん", "Hyogo", .kansai)
        case .nara: return ("奈良県", "ならけん", "Nara", .kansai)
        case .wakayama: return ("和歌山県", "わかやまけん", "Wakayama", .kansai)
        case .tottori: return ("鳥取県", "とっとりけん", "Tottori", .chugoku)
        case .shimane: return ("島根県", "しまねけん", "Shimane", .chugoku)
        case .okayama: return ("岡山県", "おかやまけん", "Okayama", .chugoku)
        case .hiroshima: return ("広島県", "ひろしまけん", "Hiroshima", .chugoku)
        case .yamaguchi: return ("山口県", "やまぐちけん", "Yamaguchi", .chugoku)
        case .tokushima: return ("徳島県", "とくしまけん", "Tokushima", .shikoku)
        case .kagawa: return ("香川県", "かがわけん", "Kagawa", .shikoku)
        case .ehime: return ("愛媛県", "えひめけん", "Ehime", .shikoku)
        case .kochi: return ("高知県", "こうちけん", "Kochi", .shikoku)
        case .fukuoka: return ("福岡県", "ふくおかけん", "Fukuoka", .kyushuOkinawa)
        case .saga: return ("佐賀県", "さがけん", "Saga", .kyushuOkinawa)
        case .nagasaki: return ("長崎県", "ながさきけん", "Nagasaki", .kyushuOkinawa)
        case .kumamoto: return ("熊本県", "くまもとけん", "Kumamoto", .kyushuOkinawa)
        case .oita: return ("大分県", "おおいたけん", "Oita", .kyushuOkinawa)
        case .miyazaki: return ("宮崎県", "みやざきけん", "Miyazaki", .kyushuOkinawa)
        case .kagoshima: return ("鹿児島県", "かごしまけん", "Kagoshima", .kyushuOkinawa)
        case .okinawa: return ("沖縄県", "おきなわけん", "Okinawa", .kyushuOkinawa)
        }
    }

    /// 熊本県, 東京都, 北海道.
    public var name: String { info.name }
    /// くまもとけん.
    public var kana: String { info.kana }
    /// Kumamoto (no macrons, so it matches what people type).
    public var romaji: String { info.romaji }
    public var region: Region { info.region }
}
