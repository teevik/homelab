//! Homelab laptop health dashboard: the approved Instrument ledger for the Linux
//! console, drawn from generated catalog metadata and local collector snapshots.

pub mod contract;
mod dashboard;
pub mod health;
mod ui;
pub mod fixtures;
pub mod palette;
pub mod text;

pub use dashboard::{Dashboard, KeyOutcome};
