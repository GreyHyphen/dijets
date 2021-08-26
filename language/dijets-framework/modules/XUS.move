/// This module defines the coin type XUS and its initialization function.
module DijetsFramework::XUS {
    use DijetsFramework::AccountLimits;
    use DijetsFramework::Dijets;
    use DijetsFramework::DijetsTimestamp;
    use DijetsFramework::Roles;
    use Std::FixedPoint32;

    /// The type tag representing the `XUS` currency on-chain.
    struct XUS { }

    /// Registers the `XUS` cointype. This can only be called from genesis.
    public fun initialize(
        dr_account: &signer,
        tc_account: &signer,
    ) {
        DijetsTimestamp::assert_genesis();
        Roles::assert_treasury_compliance(tc_account);
        Roles::assert_dijets_root(dr_account);
        Dijets::register_SCS_currency<XUS>(
            dr_account,
            tc_account,
            FixedPoint32::create_from_rational(1, 1), // exchange rate to XDX
            1000000, // scaling_factor = 10^6
            100,     // fractional_part = 10^2
            b"XUS"
        );
        AccountLimits::publish_unrestricted_limits<XUS>(dr_account);
    }
    spec initialize {
        use DijetsFramework::Roles;
        include Dijets::RegisterSCSCurrencyAbortsIf<XUS>{
            currency_code: b"XUS",
            scaling_factor: 1000000
        };
        include AccountLimits::PublishUnrestrictedLimitsAbortsIf<XUS>{publish_account: dr_account};
        include Dijets::RegisterSCSCurrencyEnsures<XUS>;
        include AccountLimits::PublishUnrestrictedLimitsEnsures<XUS>{publish_account: dr_account};
        /// Registering XUS can only be done in genesis.
        include DijetsTimestamp::AbortsIfNotGenesis;
        /// Only the DijetsRoot account can register a new currency [[H8]][PERMISSION].
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};
        /// Only a TreasuryCompliance account can have the MintCapability [[H1]][PERMISSION].
        /// Moreover, only a TreasuryCompliance account can have the BurnCapability [[H3]][PERMISSION].
        include Roles::AbortsIfNotTreasuryCompliance{account: tc_account};
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Persistence of Resources
    spec module {
        /// After genesis, XUS is registered.
        invariant DijetsTimestamp::is_operating() ==> Dijets::is_currency<XUS>();

        /// After genesis, `LimitsDefinition<XUS>` is published at Dijets root. It's published by
        /// AccountLimits::publish_unrestricted_limits, but we can't prove the condition there because
        /// it does not hold for all types (but does hold for XUS).
        invariant DijetsTimestamp::is_operating()
            ==> exists<AccountLimits::LimitsDefinition<XUS>>(@DijetsRoot);

        /// `LimitsDefinition<XUS>` is not published at any other address
        invariant forall addr: address where exists<AccountLimits::LimitsDefinition<XUS>>(addr):
            addr == @DijetsRoot;

    }
}
