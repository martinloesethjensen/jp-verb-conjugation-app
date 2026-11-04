//! Where published files come from. The Worker fetches them from raw.githubusercontent.com; the tests
//! serve them from memory.

#[allow(async_fn_in_trait)]
pub trait Source {
    /// The body at `url`. Anything but a 200 is an `Err`.
    async fn get(&self, url: &str) -> Result<Vec<u8>, String>;
}
