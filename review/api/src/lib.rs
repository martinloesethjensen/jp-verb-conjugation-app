//! The review site API. Pure modules build and test natively; the Worker glue is wasm32 only.

pub mod access;
pub mod app;
pub mod auth;
pub mod data;
pub mod store;

#[cfg(target_arch = "wasm32")]
mod d1;
#[cfg(target_arch = "wasm32")]
mod worker_glue;
