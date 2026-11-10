//! The review site API. Pure modules build and test natively; the Worker glue is wasm32 only.

pub mod access;
pub mod add_routes;
pub mod addition;
pub mod app;
pub mod auth;
pub mod data;
pub mod export_routes;
pub mod items;
pub mod manifest;
pub mod proposal;
pub mod reply_routes;
pub mod review_routes;
pub mod review_store;
pub mod source;
pub mod stamp_routes;
pub mod store;

#[cfg(target_arch = "wasm32")]
mod d1;
#[cfg(target_arch = "wasm32")]
mod worker_glue;
