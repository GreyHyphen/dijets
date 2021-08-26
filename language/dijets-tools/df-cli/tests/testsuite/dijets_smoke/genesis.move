script {
    use DijetsFramework::AccountFreezing;
    use DijetsFramework::ChainId;
    use DijetsFramework::XUS;
    use DijetsFramework::DualAttestation;
    use DijetsFramework::XDX;
    use DijetsFramework::Dijets;
    use DijetsFramework::DijetsAccount;
    use DijetsFramework::DijetsBlock;
    use DijetsFramework::DijetsConfig;
    use DijetsFramework::DijetsSystem;
    use DijetsFramework::DijetsTimestamp;
    use DijetsFramework::DijetsTransactionPublishingOption;
    use DijetsFramework::DijetsVersion;
    use DijetsFramework::TransactionFee;
    use DijetsFramework::DijetsVMConfig;
    use Std::Vector;

    fun initialize(
        dr_account: signer,
        tc_account: signer,
    ) {
        let dr_account = &dr_account;
        let tc_account = &tc_account;
        let dummy_auth_key = x"0000000000000000000000000000000000000000000000000000000000000000";
        let dr_auth_key = copy dummy_auth_key;
        let tc_auth_key = dummy_auth_key;

        // no script allowlist + allow open publishing
        let initial_script_allow_list = Vector::empty();
        let is_open_module = true;
        let instruction_schedule = Vector::empty();
        let native_schedule = Vector::empty();
        let chain_id = 0;
        let initial_dijets_version = 1;

        DijetsAccount::initialize(dr_account, x"00000000000000000000000000000000");

        ChainId::initialize(dr_account, chain_id);

        // On-chain config setup
        DijetsConfig::initialize(dr_account);

        // Currency setup
        Dijets::initialize(dr_account);

        // Currency setup
        XUS::initialize(dr_account, tc_account);

        XDX::initialize(
            dr_account,
            tc_account,
        );

        AccountFreezing::initialize(dr_account);

        TransactionFee::initialize(tc_account);

        DijetsSystem::initialize_validator_set(dr_account);
        DijetsVersion::initialize(dr_account, initial_dijets_version);
        DualAttestation::initialize(dr_account);
        DijetsBlock::initialize_block_metadata(dr_account);

        let dr_rotate_key_cap = DijetsAccount::extract_key_rotation_capability(dr_account);
        DijetsAccount::rotate_authentication_key(&dr_rotate_key_cap, dr_auth_key);
        DijetsAccount::restore_key_rotation_capability(dr_rotate_key_cap);

        DijetsTransactionPublishingOption::initialize(
            dr_account,
            initial_script_allow_list,
            is_open_module,
        );

        DijetsVMConfig::initialize(
            dr_account,
            instruction_schedule,
            native_schedule,
        );

        let tc_rotate_key_cap = DijetsAccount::extract_key_rotation_capability(tc_account);
        DijetsAccount::rotate_authentication_key(&tc_rotate_key_cap, tc_auth_key);
        DijetsAccount::restore_key_rotation_capability(tc_rotate_key_cap);
        DijetsTimestamp::set_time_has_started(dr_account);
    }

}
