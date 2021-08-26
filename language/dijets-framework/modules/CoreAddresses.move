/// Module providing well-known addresses and related logic.
///
/// > Note: this module currently defines zero-argument functions like `Self::DIJETS_ROOT_ADDRESS()` using capitalization
/// > in the name, following the convention for constants. Eventually, those functions are planned to become actual
/// > global constants, once the Move language supports this feature.
module DijetsFramework::CoreAddresses {
    use Std::Errors;
    use Std::Signer;

    /// The operation can only be performed by the account at 0xA550C18 (Dijets Root)
    const EDIJETS_ROOT: u64 = 0;
    /// The operation can only be performed by the account at 0xB1E55ED (Treasury & Compliance)
    const ETREASURY_COMPLIANCE: u64 = 1;
    /// The operation can only be performed by the VM
    const EVM: u64 = 2;
    /// The operation can only be performed by the account where currencies are registered
    const ECURRENCY_INFO: u64 = 3;

    /// Assert that the account is the Dijets root address.
    public fun assert_dijets_root(account: &signer) {
        assert(Signer::address_of(account) == @DijetsRoot, Errors::requires_address(EDIJETS_ROOT))
    }
    spec assert_dijets_root {
        pragma opaque;
        include AbortsIfNotDijetsRoot;
    }

    /// Specifies that a function aborts if the account does not have the Dijets root address.
    spec schema AbortsIfNotDijetsRoot {
        account: signer;
        aborts_if Signer::spec_address_of(account) != @DijetsRoot with Errors::REQUIRES_ADDRESS;
    }

    /// Assert that the signer has the treasury compliance address.
    public fun assert_treasury_compliance(account: &signer) {
        assert(
            Signer::address_of(account) == @TreasuryCompliance,
            Errors::requires_address(ETREASURY_COMPLIANCE)
        )
    }
    spec assert_treasury_compliance {
        pragma opaque;
        include AbortsIfNotTreasuryCompliance;
    }

    /// Specifies that a function aborts if the account does not have the treasury compliance address.
    spec schema AbortsIfNotTreasuryCompliance {
        account: signer;
        aborts_if Signer::spec_address_of(account) != @TreasuryCompliance
            with Errors::REQUIRES_ADDRESS;
    }

    /// Assert that the signer has the VM reserved address.
    public fun assert_vm(account: &signer) {
        assert(Signer::address_of(account) == @VMReserved, Errors::requires_address(EVM))
    }
    spec assert_vm {
        pragma opaque;
        include AbortsIfNotVM;
    }

    /// Specifies that a function aborts if the account does not have the VM reserved address.
    spec schema AbortsIfNotVM {
        account: signer;
        aborts_if Signer::spec_address_of(account) != @VMReserved with Errors::REQUIRES_ADDRESS;
    }

    /// Assert that the signer has the currency info address.
    public fun assert_currency_info(account: &signer) {
        assert(Signer::address_of(account) == @CurrencyInfo, Errors::requires_address(ECURRENCY_INFO))
    }
    spec assert_currency_info {
        pragma opaque;
        include AbortsIfNotCurrencyInfo;
    }

    /// Specifies that a function aborts if the account has not the currency info address.
    spec schema AbortsIfNotCurrencyInfo {
        account: signer;
        aborts_if Signer::spec_address_of(account) != @CurrencyInfo with Errors::REQUIRES_ADDRESS;
    }

}
