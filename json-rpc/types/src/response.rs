// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0

use crate::errors::JsonRpcError;
use serde::{Deserialize, Serialize};

// http response header names
pub const X_DIJETS_CHAIN_ID: &str = "X-Dijets-Chain-Id";
pub const X_DIJETS_VERSION_ID: &str = "X-Dijets-Ledger-Version";
pub const X_DIJETS_TIMESTAMP_USEC_ID: &str = "X-Dijets-Ledger-TimestampUsec";

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct JsonRpcResponse {
    pub dijets_chain_id: u8,
    pub dijets_ledger_version: u64,
    pub dijets_ledger_timestampusec: u64,

    pub jsonrpc: String,

    pub id: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

impl JsonRpcResponse {
    pub fn new(
        chain_id: dijets_types::chain_id::ChainId,
        dijets_ledger_version: u64,
        dijets_ledger_timestampusec: u64,
    ) -> Self {
        Self {
            dijets_chain_id: chain_id.id(),
            dijets_ledger_version,
            dijets_ledger_timestampusec,
            jsonrpc: "2.0".to_string(),
            id: None,
            result: None,
            error: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::response::JsonRpcResponse;
    use dijets_types::chain_id::ChainId;

    #[test]
    fn test_new() {
        let resp = JsonRpcResponse::new(ChainId::test(), 1, 2);
        assert_eq!(resp.jsonrpc, "2.0");
        assert_eq!(resp.dijets_chain_id, 4);
        assert_eq!(resp.dijets_ledger_version, 1);
        assert_eq!(resp.dijets_ledger_timestampusec, 2);
        assert!(resp.id.is_none());
        assert!(resp.result.is_none());
        assert!(resp.error.is_none());
    }
}
