/// The chain id distinguishes between different chains (e.g., testnet and the main Dijets network).
/// One important role is to prevent transactions intended for one chain from being executed on another.
/// This code provides a container for storing a chain id and functions to initialize and get it.
module DijetsFramework::ChainId {
    use DijetsFramework::CoreAddresses;
    use DijetsFramework::DijetsTimestamp;
    use Std::Errors;
    use Std::Signer;

    struct ChainId has key {
        id: u8
    }

    /// The `ChainId` resource was not in the required state
    const ECHAIN_ID: u64 = 0;

    /// Publish the chain ID `id` of this Dijets instance under the DijetsRoot account
    public fun initialize(dr_account: &signer, id: u8) {
        DijetsTimestamp::assert_genesis();
        CoreAddresses::assert_dijets_root(dr_account);
        assert(!exists<ChainId>(Signer::address_of(dr_account)), Errors::already_published(ECHAIN_ID));
        move_to(dr_account, ChainId { id })
    }

    spec initialize {
        pragma opaque;
        let dr_addr = Signer::address_of(dr_account);
        modifies global<ChainId>(dr_addr);
        include DijetsTimestamp::AbortsIfNotGenesis;
        include CoreAddresses::AbortsIfNotDijetsRoot{account: dr_account};
        aborts_if exists<ChainId>(dr_addr) with Errors::ALREADY_PUBLISHED;
        ensures exists<ChainId>(dr_addr);
    }

    /// Return the chain ID of this Dijets instance
    public fun get(): u8 acquires ChainId {
        DijetsTimestamp::assert_operating();
        borrow_global<ChainId>(@DijetsRoot).id
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Initialization

    spec module {
        /// When Dijets is operating, the chain id is always available.
        invariant DijetsTimestamp::is_operating() ==> exists<ChainId>(@DijetsRoot);

        // Could also specify that ChainId is not stored on any other address, but it doesn't matter.
    }

    /// # Helper Functions

    spec fun spec_get_chain_id(): u8 {
        global<ChainId>(@DijetsRoot).id
    }
}
