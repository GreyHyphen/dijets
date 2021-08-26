// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0
//! Names of modules, functions, and types used by Dijets System.

use dijets_types::account_config;
use move_core_types::{ident_str, identifier::IdentStr, language_storage::ModuleId};
use once_cell::sync::Lazy;

// Data to resolve basic account and transaction flow functions and structs
/// The ModuleId for the dijets writeset manager module
/// The ModuleId for the dijets block module
pub static DIJETS_BLOCK_MODULE: Lazy<ModuleId> = Lazy::new(|| {
    ModuleId::new(
        account_config::CORE_CODE_ADDRESS,
        ident_str!("DijetsBlock").to_owned(),
    )
});

// Names for special functions and structs
pub const SCRIPT_PROLOGUE_NAME: &IdentStr = ident_str!("script_prologue");
pub const MULTI_AGENT_SCRIPT_PROLOGUE_NAME: &IdentStr = ident_str!("multi_agent_script_prologue");
pub const MODULE_PROLOGUE_NAME: &IdentStr = ident_str!("module_prologue");
pub const WRITESET_PROLOGUE_NAME: &IdentStr = ident_str!("writeset_prologue");
pub const WRITESET_EPILOGUE_NAME: &IdentStr = ident_str!("writeset_epilogue");
pub const USER_EPILOGUE_NAME: &IdentStr = ident_str!("epilogue");
pub const BLOCK_PROLOGUE: &IdentStr = ident_str!("block_prologue");
