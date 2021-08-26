// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0

//! # Tool to help maintaining dijets specifications.
//!
//! '''bash
//! cargo run -p dijets-documentation-tool -- --help
//! '''

use dijets_documentation_tool as dijets_doc;
use serde_reflection::Registry;
use std::{collections::BTreeMap, path::PathBuf};
use structopt::StructOpt;

#[derive(Debug, StructOpt)]
#[structopt(
    name = "dijets documentation tool",
    about = "Tool to help maintaining dijets specifications"
)]
struct Options {
    /// Path to the YAML-encoded Serde formats.
    #[structopt(parse(from_os_str))]
    input: PathBuf,

    /// Directory where to update markdown files in place (otherwise print sample code on stdout).
    #[structopt(long)]
    update_dijets_specs_dir: Option<PathBuf>,
}

fn process_specs(dir: PathBuf, definitions: &BTreeMap<String, String>) -> std::io::Result<()> {
    for entry in std::fs::read_dir(dir.as_path())? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            continue;
        }
        let file = std::io::BufReader::new(std::fs::File::open(path.clone())?);
        let output = dijets_doc::update_rust_quotes(file, definitions)?;
        std::fs::write(path, &output)?;
    }
    Ok(())
}

fn main() {
    let options = Options::from_args();
    let content = std::fs::read_to_string(options.input).expect("input file amust be readable");
    let registry = serde_yaml::from_str::<Registry>(content.as_str())
        .expect("input file should be correct YAML for a Serde registry");

    let definitions = dijets_doc::quote_container_definitions(&registry)
        .expect("generating definitions should not fail");

    match options.update_dijets_specs_dir {
        None => println!("{:#?}", definitions),
        Some(dir) => process_specs(dir, &definitions).expect("failed to process specifications"),
    }
}
