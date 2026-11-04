use review_api::data::DataFile;
use review_api::items::{extract, extract_slice, slices, Slice, SLICE_BYTES};
use serde_json::Value;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn real(file: DataFile) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap()
}

const BROWSABLE: [DataFile; 4] = [
    DataFile::Verbs,
    DataFile::Words,
    DataFile::Counters,
    DataFile::Grammar,
];

#[test]
fn slices_cover_every_entry_once_in_order() {
    for file in BROWSABLE {
        let bytes = real(file);
        let ranges = slices(file, &bytes).unwrap();
        let entries = serde_json::from_slice::<Value>(&bytes).unwrap()[file.name()]
            .as_array()
            .unwrap()
            .len();
        assert_eq!(ranges.first().unwrap().entries.start, 0, "{}", file.name());
        assert_eq!(
            ranges.last().unwrap().entries.end,
            entries,
            "{}",
            file.name()
        );
        for pair in ranges.windows(2) {
            assert_eq!(
                pair[0].entries.end,
                pair[1].entries.start,
                "{}",
                file.name()
            );
            assert!(pair[0].bytes.end < pair[1].bytes.start, "{}", file.name());
        }
        assert!(ranges
            .iter()
            .all(|r| !r.entries.is_empty() && !r.bytes.is_empty()));
    }
}

#[test]
fn a_multi_entry_slice_stays_under_the_byte_budget() {
    for file in BROWSABLE {
        let bytes = real(file);
        let doc: Value = serde_json::from_slice(&bytes).unwrap();
        let entries = doc[file.name()].as_array().unwrap();
        for slice in slices(file, &bytes).unwrap() {
            if slice.entries.len() > 1 {
                let size: usize = entries[slice.entries.clone()]
                    .iter()
                    .map(|e| e.to_string().len())
                    .sum();
                assert!(
                    size <= SLICE_BYTES,
                    "{} {:?}: {size} bytes",
                    file.name(),
                    slice.entries
                );
                assert!(
                    slice.bytes.len() <= SLICE_BYTES + slice.entries.len() * 4,
                    "{}",
                    file.name()
                );
            }
        }
    }
    assert!(
        slices(DataFile::Verbs, &real(DataFile::Verbs))
            .unwrap()
            .len()
            > 1,
        "verbs is split"
    );
}

#[test]
fn slice_rows_add_up_to_the_whole_file() {
    for file in BROWSABLE {
        let bytes = real(file);
        let mut joined = Vec::new();
        for slice in slices(file, &bytes).unwrap() {
            joined.extend(extract_slice(file, &bytes, &slice).unwrap());
        }
        assert_eq!(joined, extract(file, &bytes).unwrap(), "{}", file.name());
        assert!(
            joined.windows(2).all(|w| w[0].position < w[1].position),
            "{}: positions",
            file.name()
        );
    }
}

#[test]
fn reference_files_have_no_slices() {
    assert!(slices(DataFile::Furigana, &real(DataFile::Furigana))
        .unwrap()
        .is_empty());
    assert!(slices(DataFile::Forms, &real(DataFile::Forms))
        .unwrap()
        .is_empty());
    assert!(slices(DataFile::Furigana, b"[]").is_err());
}

#[test]
fn a_bad_entry_fails_only_its_slice_and_a_bad_top_level_fails_slicing() {
    let mut doc: Value = serde_json::from_slice(&real(DataFile::Verbs)).unwrap();
    let last = doc["verbs"].as_array().unwrap().len() - 1;
    doc["verbs"][last]["romaji"] = "x".into();
    let bytes = serde_json::to_vec(&doc).unwrap();
    let ranges = slices(DataFile::Verbs, &bytes).unwrap();
    assert!(extract_slice(DataFile::Verbs, &bytes, &ranges[0]).is_ok());
    assert!(extract_slice(DataFile::Verbs, &bytes, ranges.last().unwrap()).is_err());

    let mut top = serde_json::from_slice::<Value>(&real(DataFile::Verbs)).unwrap();
    top["extra"] = "x".into();
    assert!(slices(DataFile::Verbs, &serde_json::to_vec(&top).unwrap()).is_err());
    assert!(slices(DataFile::Verbs, b"{}").is_err());
}

#[test]
fn a_slice_that_doesnt_fit_the_bytes_is_refused() {
    let bytes = real(DataFile::Words);
    let mut slice = slices(DataFile::Words, &bytes).unwrap().remove(0);
    slice.bytes.start += 1; // cuts the first entry's opening brace: no longer a run of whole entries
    assert!(extract_slice(DataFile::Words, &bytes, &slice).is_err());
    let beyond = Slice {
        entries: 0..1,
        bytes: bytes.len()..bytes.len() + 10,
    };
    assert!(extract_slice(DataFile::Words, &bytes, &beyond).is_err());
}
