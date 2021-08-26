/// Maintains the version number for the Dijets blockchain. The version is stored in a
/// DijetsConfig, and may be updated by Dijets root.
module DijetsFramework::DijetsVersion {
    use DijetsFramework::DijetsConfig::{Self, DijetsConfig};
    use DijetsFramework::DijetsTimestamp;
    use DijetsFramework::Roles;
    use Std::Errors;

    struct DijetsVersion has copy, drop, store {
        major: u64,
    }

    /// Tried to set an invalid major version for the VM. Major versions must be strictly increasing
    const EINVALID_MAJOR_VERSION_NUMBER: u64 = 0;

    /// Publishes the DijetsVersion config. Must be called during Genesis.
    public fun initialize(dr_account: &signer, initial_version: u64) {
        DijetsTimestamp::assert_genesis();
        Roles::assert_dijets_root(dr_account);
        DijetsConfig::publish_new_config<DijetsVersion>(
            dr_account,
            DijetsVersion { major: initial_version },
        );
    }
    spec initialize {
        /// Must abort if the signer does not have the DijetsRoot role [[H10]][PERMISSION].
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};

        include DijetsTimestamp::AbortsIfNotGenesis;
        include DijetsConfig::PublishNewConfigAbortsIf<DijetsVersion>;
        include DijetsConfig::PublishNewConfigEnsures<DijetsVersion>{payload: DijetsVersion { major: initial_version }};
    }

    /// Allows Dijets root to update the major version to a larger version.
    public fun set(dr_account: &signer, major: u64) {
        DijetsTimestamp::assert_operating();

        Roles::assert_dijets_root(dr_account);

        let old_config = DijetsConfig::get<DijetsVersion>();

        assert(
            old_config.major < major,
            Errors::invalid_argument(EINVALID_MAJOR_VERSION_NUMBER)
        );

        DijetsConfig::set<DijetsVersion>(
            dr_account,
            DijetsVersion { major }
        );
    }
    spec set {
        /// Must abort if the signer does not have the DijetsRoot role [[H10]][PERMISSION].
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};

        include DijetsTimestamp::AbortsIfNotOperating;
        aborts_if DijetsConfig::get<DijetsVersion>().major >= major with Errors::INVALID_ARGUMENT;
        include DijetsConfig::SetAbortsIf<DijetsVersion>{account: dr_account};
        include DijetsConfig::SetEnsures<DijetsVersion>{payload: DijetsVersion { major }};
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Initialization
    spec module {
        /// After genesis, version is published.
        invariant DijetsTimestamp::is_operating() ==> DijetsConfig::spec_is_published<DijetsVersion>();
    }

    /// # Access Control

    /// Only "set" can modify the DijetsVersion config [[H10]][PERMISSION]
    spec schema DijetsVersionRemainsSame {
        ensures old(DijetsConfig::spec_is_published<DijetsVersion>()) ==>
            global<DijetsConfig<DijetsVersion>>(@DijetsRoot) ==
                old(global<DijetsConfig<DijetsVersion>>(@DijetsRoot));
    }
    spec module {
        apply DijetsVersionRemainsSame to * except set;
    }

    spec module {
        /// The permission "UpdateDijetsProtocolVersion" is granted to DijetsRoot [[H10]][PERMISSION].
        invariant [global, isolated] forall addr: address where exists<DijetsConfig<DijetsVersion>>(addr):
            addr == @DijetsRoot;
    }

    /// # Other Invariants
    spec module {
        /// Version number never decreases
        invariant update [global, isolated]
            old(DijetsConfig::get<DijetsVersion>().major) <= DijetsConfig::get<DijetsVersion>().major;
    }

}
