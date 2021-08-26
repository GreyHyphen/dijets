/// Maintains the consensus config for the Dijets blockchain. The config is stored in a
/// DijetsConfig, and may be updated by Dijets root.
module DijetsFramework::DijetsConsensusConfig {
    use DijetsFramework::DijetsConfig::{Self, DijetsConfig};
    use DijetsFramework::DijetsTimestamp;
    use DijetsFramework::Roles;
    use Std::Vector;

    struct DijetsConsensusConfig has copy, drop, store {
        config: vector<u8>,
    }

    /// Publishes the DijetsConsensusConfig config.
    public fun initialize(dr_account: &signer) {
        Roles::assert_dijets_root(dr_account);
        DijetsConfig::publish_new_config(dr_account, DijetsConsensusConfig { config: Vector::empty() });
    }
    spec initialize {
        /// Must abort if the signer does not have the DijetsRoot role [[H12]][PERMISSION].
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};

        include DijetsConfig::PublishNewConfigAbortsIf<DijetsConsensusConfig>;
        include DijetsConfig::PublishNewConfigEnsures<DijetsConsensusConfig>{
            payload: DijetsConsensusConfig { config: Vector::empty() }
        };
    }

    /// Allows Dijets root to update the config.
    public fun set(dr_account: &signer, config: vector<u8>) {
        DijetsTimestamp::assert_operating();

        Roles::assert_dijets_root(dr_account);

        DijetsConfig::set(
            dr_account,
            DijetsConsensusConfig { config }
        );
    }
    spec set {
        /// Must abort if the signer does not have the DijetsRoot role [[H12]][PERMISSION].
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};

        include DijetsTimestamp::AbortsIfNotOperating;
        include DijetsConfig::SetAbortsIf<DijetsConsensusConfig>{account: dr_account};
        include DijetsConfig::SetEnsures<DijetsConsensusConfig>{payload: DijetsConsensusConfig { config }};
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Access Control

    /// Only "set" can modify the DijetsConsensusConfig config [[H12]][PERMISSION]
    spec schema DijetsConsensusConfigRemainsSame {
        ensures old(DijetsConfig::spec_is_published<DijetsConsensusConfig>()) ==>
            global<DijetsConfig<DijetsConsensusConfig>>(@DijetsRoot) ==
                old(global<DijetsConfig<DijetsConsensusConfig>>(@DijetsRoot));
    }
    spec module {
        apply DijetsConsensusConfigRemainsSame to * except set;
    }

    spec module {
        /// The permission "UpdateDijetsConsensusConfig" is granted to DijetsRoot [[H12]][PERMISSION].
        invariant [global, isolated] forall addr: address where exists<DijetsConfig<DijetsConsensusConfig>>(addr):
            addr == @DijetsRoot;
    }
}
