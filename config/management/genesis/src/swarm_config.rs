// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0

use crate::validator_builder::ValidatorBuilder;
use anyhow::Result;
use dijets_config::config::{NodeConfig, OnDiskStorageConfig};
use dijets_crypto::ed25519::Ed25519PrivateKey;
use dijets_global_constants::{DIJETS_ROOT_KEY, TREASURY_COMPLIANCE_KEY};
use dijets_secure_storage::{CryptoStorage, OnDiskStorage};
use dijets_types::waypoint::Waypoint;
use std::{
    fs::File,
    io::Write,
    path::{Path, PathBuf},
};

pub trait BuildSwarm {
    /// Generate the configs for a swarm
    fn build_swarm<R>(&self, rng: R) -> Result<(Vec<NodeConfig>, Ed25519PrivateKey)>
    where
        R: ::rand::RngCore + ::rand::CryptoRng;
}

pub struct SwarmConfig {
    pub config_files: Vec<PathBuf>,
    pub dijets_root_key_path: PathBuf,
    pub root_storage: OnDiskStorageConfig,
    pub waypoint: Waypoint,
}

impl SwarmConfig {
    pub fn build_with_rng<T, R>(config_builder: &T, output_dir: &Path, rng: R) -> Result<Self>
    where
        T: BuildSwarm,
        R: ::rand::RngCore + ::rand::CryptoRng,
    {
        let (mut configs, dijets_root_key) = config_builder.build_swarm(rng)?;
        let mut config_files = vec![];

        for (index, config) in configs.iter_mut().enumerate() {
            let node_dir = output_dir.join(index.to_string());
            std::fs::create_dir_all(&node_dir)?;

            let node_path = node_dir.join("node.yaml");
            config.set_data_dir(node_dir);
            config.save(&node_path)?;
            config_files.push(node_path);
        }

        let dijets_root_key_path = output_dir.join("mint.key");
        let serialized_keys = bcs::to_bytes(&dijets_root_key)?;
        let mut key_file = File::create(&dijets_root_key_path)?;
        key_file.write_all(&serialized_keys)?;

        let mut root_storage_config = OnDiskStorageConfig::default();
        root_storage_config.path = output_dir.join("root-storage.json");
        let mut root_storage = OnDiskStorage::new(root_storage_config.path());
        root_storage.import_private_key(DIJETS_ROOT_KEY, dijets_root_key)?;
        let dijets_root_key = root_storage.export_private_key(DIJETS_ROOT_KEY).unwrap();
        root_storage.import_private_key(TREASURY_COMPLIANCE_KEY, dijets_root_key)?;

        Ok(SwarmConfig {
            config_files,
            dijets_root_key_path,
            root_storage: root_storage_config,
            waypoint: configs[0].base.waypoint.waypoint(),
        })
    }

    pub fn build<T: BuildSwarm>(config_builder: &T, output_dir: &Path) -> Result<Self> {
        Self::build_with_rng(config_builder, output_dir, rand::rngs::OsRng)
    }
}

impl BuildSwarm for ValidatorBuilder {
    fn build_swarm<R>(&self, rng: R) -> Result<(Vec<NodeConfig>, Ed25519PrivateKey)>
    where
        R: ::rand::RngCore + ::rand::CryptoRng,
    {
        let (root_keys, validators) = self.clone().build(rng)?;

        Ok((
            validators.into_iter().map(|v| v.config).collect(),
            root_keys.root_key,
        ))
    }
}
