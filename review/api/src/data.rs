//! Strict types for the published data files, mirrored from `schema/*.schema.json`.
//!
//! The JSON Schemas are the contract; these types are tested against the real `data/` files and
//! `schema/fixtures/invalid.json`. They check required keys, unknown keys (rejected everywhere) and
//! enum values. Patterns (stable ids, kana, slugs) are left to `update_data.py`, which enforces them
//! before anything is published.

use serde::Deserialize;
use std::collections::BTreeMap;

/// A published file in `data/`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DataFile {
    Verbs,
    Words,
    Counters,
    Grammar,
    Furigana,
    Forms,
}

impl DataFile {
    /// Every file, in the order the admin page loads them: reference files first.
    pub const ALL: [DataFile; 6] = [
        DataFile::Furigana,
        DataFile::Forms,
        DataFile::Words,
        DataFile::Counters,
        DataFile::Grammar,
        DataFile::Verbs,
    ];

    pub fn name(self) -> &'static str {
        match self {
            DataFile::Verbs => "verbs",
            DataFile::Words => "words",
            DataFile::Counters => "counters",
            DataFile::Grammar => "grammar",
            DataFile::Furigana => "furigana",
            DataFile::Forms => "forms",
        }
    }

    pub fn file_name(self) -> &'static str {
        match self {
            DataFile::Verbs => "verbs.json",
            DataFile::Words => "words.json",
            DataFile::Counters => "counters.json",
            DataFile::Grammar => "grammar.json",
            DataFile::Furigana => "furigana.json",
            DataFile::Forms => "forms.json",
        }
    }

    /// `"verbs"` → `Verbs`. Only the bare names; anything else is `None`.
    pub fn parse_name(name: &str) -> Option<DataFile> {
        DataFile::ALL.into_iter().find(|f| f.name() == name)
    }

    /// The datasets reviewers browse. Furigana and forms are reference data for display.
    pub fn is_browsable(self) -> bool {
        matches!(
            self,
            DataFile::Verbs | DataFile::Words | DataFile::Counters | DataFile::Grammar
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum Jlpt {
    N5,
    N4,
    N3,
    N2,
    N1,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum WordClass {
    Verb,
    IAdjective,
    NaAdjective,
    Noun,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum Particle {
    #[serde(rename = "は")]
    Wa,
    #[serde(rename = "が")]
    Ga,
    #[serde(rename = "を")]
    Wo,
    #[serde(rename = "に")]
    Ni,
    #[serde(rename = "で")]
    De,
    #[serde(rename = "へ")]
    He,
    #[serde(rename = "と")]
    To,
    #[serde(rename = "も")]
    Mo,
    #[serde(rename = "から")]
    Kara,
    #[serde(rename = "まで")]
    Made,
    #[serde(rename = "の")]
    No,
    #[serde(rename = "や")]
    Ya,
    #[serde(rename = "より")]
    Yori,
    #[serde(rename = "か")]
    Ka,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ParticleBlank {
    pub particle: Particle,
    pub at: i64,
    #[serde(default)]
    pub accept_also: Option<Vec<Particle>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReviewStamp {
    pub by: Reviewer,
    pub on: String,
    pub sha256: String,
    /// The reviewer's public name, when they chose one.
    #[serde(default)]
    pub name: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Reviewer {
    Owner,
    Teacher,
    Native,
}

// --- verbs.json ---------------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VerbsFile {
    pub version: String,
    pub description: String,
    pub verbs: Vec<Verb>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum VerbType {
    #[serde(rename = "ru")]
    Ru,
    #[serde(rename = "u")]
    U,
    #[serde(rename = "irr.")]
    Irregular,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum VerbLabel {
    #[serde(rename = "Ru-verb")]
    RuVerb,
    #[serde(rename = "U-verb")]
    UVerb,
    #[serde(rename = "Irregular")]
    Irregular,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TeGroup {
    Ide,
    Ite,
    Nde,
    Shite,
    Tte,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Verb {
    #[serde(rename = "type")]
    pub verb_type: VerbType,
    pub label: VerbLabel,
    pub dict: String,
    pub meaning: String,
    pub description: String,
    pub notes: String,
    pub jlpt: Jlpt,
    pub forms: BTreeMap<String, String>,
    pub examples: Vec<VerbExample>,
    #[serde(default)]
    pub collocations: Option<Vec<Collocation>>,
    /// The verb's transitive/intransitive partner (#58). Authored, so it is part of the entry's hash.
    #[serde(default)]
    pub pair: Option<VerbPair>,
    #[serde(default)]
    pub id: Option<String>,
    /// A string, `null` or missing (the schema allows all three).
    #[serde(default)]
    pub kanji: Option<String>,
    #[serde(default, rename = "teGroup")]
    pub te_group: Option<TeGroup>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VerbExample {
    pub id: String,
    pub form: String,
    pub jp: String,
    pub en: String,
    #[serde(default)]
    pub particle_blanks: Option<Vec<ParticleBlank>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Collocation {
    pub id: String,
    pub jp: String,
    pub en: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VerbPair {
    /// The partner verb's id.
    pub verb: String,
    pub transitivity: Transitivity,
    pub jp: String,
    pub en: String,
}

#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Transitivity {
    Transitive,
    Intransitive,
}

// --- words.json ---------------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WordsFile {
    pub version: String,
    pub description: String,
    pub words: Vec<Word>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum WordKind {
    IAdjective,
    NaAdjective,
    Noun,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Word {
    pub class: WordKind,
    pub dict: String,
    pub meaning: String,
    pub jlpt: Jlpt,
    pub forms: BTreeMap<String, String>,
    #[serde(default)]
    pub kanji: Option<String>,
}

// --- counters.json ------------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CountersFile {
    pub version: String,
    pub description: String,
    pub counters: Vec<Counter>,
    pub groups: Vec<CounterGroup>,
    #[serde(default)]
    pub sections: Option<Vec<CounterSection>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum Sound {
    #[serde(rename = "h-b")]
    HB,
    #[serde(rename = "h-p")]
    HP,
    #[serde(rename = "irregular")]
    Irregular,
    #[serde(rename = "k")]
    K,
    #[serde(rename = "plain")]
    Plain,
    #[serde(rename = "s")]
    S,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Fit {
    Primary,
    Casual,
    Acceptable,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Counter {
    pub id: String,
    pub counter: String,
    pub reading: String,
    pub meaning: String,
    pub jlpt: Jlpt,
    pub sound: Sound,
    pub symbol: String,
    pub overrides: BTreeMap<String, Vec<String>>,
    pub things: Vec<CounterThing>,
    pub examples: Vec<CounterExample>,
    pub pitfalls: Vec<CounterPitfall>,
    pub readings: BTreeMap<String, Vec<String>>,
    pub changed: Vec<String>,
    pub distractors: BTreeMap<String, Vec<String>>,
    pub related: Vec<String>,
    #[serde(default)]
    pub compound: Option<BTreeMap<String, Vec<String>>>,
    #[serde(default, rename = "countsObjects")]
    pub counts_objects: Option<bool>,
    #[serde(default)]
    pub extent: Option<i64>,
    #[serde(default)]
    pub extra: Option<Vec<i64>>,
    #[serde(default)]
    pub questions: Option<Vec<CounterQuestion>>,
    #[serde(default)]
    pub review: Option<ReviewStamp>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CounterThing {
    pub id: String,
    pub word: String,
    pub kana: String,
    pub meaning: String,
    pub fit: Fit,
    #[serde(default)]
    pub symbol: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CounterExample {
    pub id: String,
    pub jp: String,
    pub en: String,
    #[serde(default)]
    pub readings: Option<BTreeMap<String, String>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CounterPitfall {
    pub id: String,
    pub heading: String,
    pub explanation: String,
    #[serde(default)]
    pub wrong: Option<String>,
    #[serde(default)]
    pub examples: Option<Vec<CounterExample>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CounterQuestion {
    pub jp: String,
    pub en: String,
    #[serde(default)]
    pub readings: Option<BTreeMap<String, String>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CounterGroup {
    pub id: String,
    pub title: String,
    pub symbol: String,
    pub summary: String,
    pub members: Vec<GroupMember>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GroupMember {
    pub counter: String,
    pub note: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CounterSection {
    pub id: String,
    pub title: String,
    pub counters: Vec<String>,
}

// --- grammar.json -------------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrammarFile {
    pub version: String,
    pub description: String,
    pub grammar: Vec<GrammarPoint>,
    #[serde(default)]
    pub books: Option<Vec<Book>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Book {
    pub id: String,
    pub title: String,
    pub edition: String,
    pub lessons: i64,
    #[serde(default)]
    pub first_lesson: Option<i64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrammarPoint {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub jlpt: Jlpt,
    pub usages: Vec<Usage>,
    pub attachment: Vec<Attachment>,
    pub conjugations: Vec<Conjugation>,
    pub pitfalls: Vec<GrammarPitfall>,
    pub related: Vec<String>,
    #[serde(default)]
    pub taught_in: Option<Vec<TaughtIn>>,
    #[serde(default)]
    pub contrasts: Option<Vec<Contrast>>,
    #[serde(default)]
    pub review: Option<ReviewStamp>,
    #[serde(default)]
    pub keywords: Option<Vec<String>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Usage {
    pub id: String,
    pub heading: String,
    pub explanation: String,
    pub examples: Vec<GrammarExample>,
    #[serde(default)]
    pub jlpt: Option<Jlpt>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrammarExample {
    pub id: String,
    pub jp: String,
    pub en: String,
    #[serde(default)]
    pub particle_blanks: Option<Vec<ParticleBlank>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GrammarPitfall {
    pub id: String,
    pub heading: String,
    pub explanation: String,
    #[serde(default)]
    pub wrong: Option<String>,
    #[serde(default)]
    pub examples: Option<Vec<GrammarExample>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Attachment {
    pub word_class: WordClass,
    pub pattern: String,
    pub example: String,
    #[serde(default)]
    pub condition: Option<String>,
    #[serde(default)]
    pub da_to_na: Option<bool>,
    #[serde(default)]
    pub note: Option<String>,
    #[serde(default)]
    pub slots: Option<Vec<String>>,
    #[serde(default)]
    pub then: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Register {
    Casual,
    Formal,
    Polite,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Conjugation {
    pub form: String,
    pub register: Register,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Contrast {
    pub pattern: String,
    pub explanation: String,
    pub examples: Vec<GrammarExample>,
    /// Names another grammar point, not a stable id.
    #[serde(default)]
    pub id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaughtIn {
    pub book: String,
    pub lesson: i64,
    pub reviewed: bool,
}

// --- furigana.json and forms.json ---------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FuriganaFile {
    pub version: String,
    pub description: String,
    pub readings: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FormsFile {
    pub schema: FormsSchema,
    pub description: String,
    pub word_classes: Vec<WordClass>,
    pub families: Vec<Family>,
    pub forms: Vec<Form>,
}

/// The schema pins `"schema": 1`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FormsSchema;

impl<'de> Deserialize<'de> for FormsSchema {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        match u64::deserialize(deserializer)? {
            1 => Ok(FormsSchema),
            other => Err(serde::de::Error::custom(format!(
                "forms schema must be 1, not {other}"
            ))),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Family {
    pub id: String,
    pub title: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FormRole {
    Connective,
    Derived,
    Finite,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FormSource {
    Authored,
    Derived,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FormRegister {
    Casual,
    Polite,
    Short,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Polarity {
    Neg,
    Pos,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tense {
    Past,
    Present,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Form {
    pub id: String,
    pub family: String,
    pub label: String,
    pub role: FormRole,
    pub applies_to: Vec<WordClass>,
    pub source: FormSource,
    #[serde(default)]
    pub register: Option<FormRegister>,
    #[serde(default)]
    pub polarity: Option<Polarity>,
    #[serde(default)]
    pub tense: Option<Tense>,
    #[serde(default)]
    pub search: Option<bool>,
    #[serde(default)]
    pub concept: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub grammar: Option<String>,
}

/// A parsed file.
#[derive(Debug, Clone)]
pub enum Parsed {
    Verbs(VerbsFile),
    Words(WordsFile),
    Counters(CountersFile),
    Grammar(GrammarFile),
    Furigana(FuriganaFile),
    Forms(FormsFile),
}

/// Checks an already-parsed document against the strict types, without parsing the bytes again.
pub fn parse_value(file: DataFile, value: &serde_json::Value) -> Result<Parsed, String> {
    fn strict<'a, T: Deserialize<'a>>(value: &'a serde_json::Value) -> Result<T, String> {
        T::deserialize(value).map_err(|e| e.to_string())
    }
    Ok(match file {
        DataFile::Verbs => Parsed::Verbs(strict(value)?),
        DataFile::Words => Parsed::Words(strict(value)?),
        DataFile::Counters => Parsed::Counters(strict(value)?),
        DataFile::Grammar => Parsed::Grammar(strict(value)?),
        DataFile::Furigana => Parsed::Furigana(strict(value)?),
        DataFile::Forms => Parsed::Forms(strict(value)?),
    })
}

/// Checks one entry of a browsable file (a verb, word, counter or grammar point) against the strict
/// types. Reference files have no entries; for them this is always an error.
pub fn check_entry(file: DataFile, entry: &serde_json::Value) -> Result<(), String> {
    fn strict<'a, T: Deserialize<'a>>(value: &'a serde_json::Value) -> Result<(), String> {
        T::deserialize(value).map(drop).map_err(|e| e.to_string())
    }
    match file {
        DataFile::Verbs => strict::<Verb>(entry),
        DataFile::Words => strict::<Word>(entry),
        DataFile::Counters => strict::<Counter>(entry),
        DataFile::Grammar => strict::<GrammarPoint>(entry),
        DataFile::Furigana | DataFile::Forms => Err(format!("{} has no entries", file.file_name())),
    }
}

/// Parses `bytes` as `file` with the strict types. The error is serde's message.
pub fn parse(file: DataFile, bytes: &[u8]) -> Result<Parsed, String> {
    fn strict<T: for<'de> Deserialize<'de>>(bytes: &[u8]) -> Result<T, String> {
        serde_json::from_slice(bytes).map_err(|e| e.to_string())
    }
    Ok(match file {
        DataFile::Verbs => Parsed::Verbs(strict(bytes)?),
        DataFile::Words => Parsed::Words(strict(bytes)?),
        DataFile::Counters => Parsed::Counters(strict(bytes)?),
        DataFile::Grammar => Parsed::Grammar(strict(bytes)?),
        DataFile::Furigana => Parsed::Furigana(strict(bytes)?),
        DataFile::Forms => Parsed::Forms(strict(bytes)?),
    })
}
