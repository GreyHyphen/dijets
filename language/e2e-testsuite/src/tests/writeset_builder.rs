// Copyright (c) The Dijets Core Contributors
// SPDX-License-Identifier: Apache-2.0
use compiler::Compiler;
use dijets_types::{
    access_path::AccessPath,
    account_config,
    on_chain_config::DijetsVersion,
    transaction::{ChangeSet, Script, TransactionStatus, WriteSetPayload},
    vm_status::KeptVMStatus,
    write_set::WriteOp,
};
use dijets_vm::DijetsVM;
use dijets_writeset_generator::build_changeset;
use language_e2e_tests::{
    account::Account, compile::compile_module_with_address, current_function_name,
    executor::FakeExecutor,
};

#[test]
fn build_upgrade_writeset() {
    let mut executor = FakeExecutor::from_genesis_file();
    executor.set_golden_file(current_function_name!());

    // create a transaction trying to publish a new module.
    let genesis_account = Account::new_dijets_root();

    let program = String::from(
        "
        module M {
            public magic(): u64 { return 42; }
        }
        ",
    );

    let module =
        compile_module_with_address(&account_config::CORE_CODE_ADDRESS, "file_name", &program).0;
    let module_bytes = {
        let mut v = vec![];
        module.serialize(&mut v).unwrap();
        v
    };
    let change_set = {
        let (version_writes, events) = build_changeset(executor.get_state_view(), |session| {
            session.set_dijets_version(11);
        })
        .into_inner();
        let mut writeset = version_writes.into_mut();
        writeset.push((
            AccessPath::code_access_path(module.self_id()),
            WriteOp::Value(module_bytes),
        ));
        ChangeSet::new(writeset.freeze().unwrap(), events)
    };

    let writeset_txn = genesis_account
        .transaction()
        .write_set(WriteSetPayload::Direct(change_set))
        .sequence_number(1)
        .sign();

    let output = executor.execute_transaction(writeset_txn.clone());
    assert_eq!(
        output.status(),
        &TransactionStatus::Keep(KeptVMStatus::Executed)
    );
    assert!(executor.verify_transaction(writeset_txn).status().is_none());

    executor.apply_write_set(output.write_set());

    let new_vm = DijetsVM::new(executor.get_state_view());
    assert_eq!(
        new_vm.internals().dijets_version().unwrap(),
        DijetsVersion { major: 11 }
    );

    let script_body = {
        let code = r#"
import 0x1.M;

main(lr_account: signer) {
  assert(M.magic() == 42, 100);
  return;
}
"#;

        let compiler = Compiler {
            address: account_config::CORE_CODE_ADDRESS,
            deps: vec![&module],
        };
        compiler
            .into_script_blob("file_name", code)
            .expect("Failed to compile")
    };

    let txn = genesis_account
        .transaction()
        .script(Script::new(script_body, vec![], vec![]))
        .sequence_number(2)
        .sign();

    let output = executor.execute_transaction(txn);
    assert_eq!(
        output.status(),
        &TransactionStatus::Keep(KeptVMStatus::Executed)
    );
}
