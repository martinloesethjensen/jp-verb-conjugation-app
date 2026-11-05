//! A `Source` serving files from memory, keyed by URL. `published()` serves the repo's real data/.

use review_api::data::DataFile;
use review_api::manifest::RAW_ROOT;
use review_api::source::Source;
use std::cell::RefCell;
use std::collections::HashMap;

#[derive(Default)]
pub struct FakeSource {
    pub files: RefCell<HashMap<String, Vec<u8>>>,
    pub requests: RefCell<Vec<String>>,
}

pub fn main_url(name: &str) -> String {
    format!("{RAW_ROOT}main/data/{name}")
}

impl FakeSource {
    pub fn empty() -> Self {
        Self::default()
    }

    pub fn published() -> Self {
        let source = Self::default();
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../../data");
        let names = DataFile::ALL
            .iter()
            .map(|f| f.file_name())
            .chain(["manifest.json", "manifest.sig"]);
        for name in names {
            source.set(name, std::fs::read(format!("{root}/{name}")).unwrap());
        }
        source
    }

    pub fn set(&self, name: &str, bytes: Vec<u8>) {
        self.files.borrow_mut().insert(main_url(name), bytes);
    }

    pub fn get_bytes(&self, name: &str) -> Vec<u8> {
        self.files.borrow()[&main_url(name)].clone()
    }

    pub fn remove(&self, name: &str) {
        self.files.borrow_mut().remove(&main_url(name));
    }
}

impl Source for FakeSource {
    async fn get(&self, url: &str) -> Result<Vec<u8>, String> {
        self.requests.borrow_mut().push(url.to_string());
        self.files
            .borrow()
            .get(url)
            .cloned()
            .ok_or_else(|| format!("404 {url}"))
    }
}
