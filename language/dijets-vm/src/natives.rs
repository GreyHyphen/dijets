// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0

use dijets_types::account_config::CORE_CODE_ADDRESS;
use move_vm_runtime::native_functions::NativeFunctionTable;

pub fn dijets_natives() -> NativeFunctionTable {
    move_stdlib::natives::all_natives(CORE_CODE_ADDRESS)
        .into_iter()
        .chain(dijets_framework::natives::all_natives(CORE_CODE_ADDRESS))
        .collect()
}
