// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0

use dijets_framework::dijets_framework_named_addresses;
use dijets_vm::natives::dijets_natives;
use move_unit_test::UnitTestingConfig;

move_unit_test::register_move_unit_tests!(
    UnitTestingConfig::default_with_bound(Some(100_000))
        .with_named_addresses(dijets_framework_named_addresses()),
    ".",
    r".*\.move$",
    &move_stdlib::move_stdlib_modules_full_path(),
    Some(dijets_natives())
);
