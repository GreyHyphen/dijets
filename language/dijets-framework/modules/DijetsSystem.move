/// Maintains information about the set of validators used during consensus.
/// Provides functions to add, remove, and update validators in the
/// validator set.
///
/// > Note: When trying to understand this code, it's important to know that "config"
/// and "configuration" are used for several distinct concepts.
module DijetsFramework::DijetsSystem {
    use DijetsFramework::DijetsConfig::{Self, ModifyConfigCapability};
    use DijetsFramework::ValidatorConfig;
    use DijetsFramework::Roles;
    use DijetsFramework::DijetsTimestamp;
    use Std::Errors;
    use Std::Option::{Self, Option};
    use Std::Signer;
    use Std::Vector;

    /// Information about a Validator Owner.
    struct ValidatorInfo has copy, drop, store {
        /// The address (account) of the Validator Owner
        addr: address,
        /// The voting power of the Validator Owner (currently always 1).
        consensus_voting_power: u64,
        /// Configuration information about the Validator, such as the
        /// Validator Operator, human name, and info such as consensus key
        /// and network addresses.
        config: ValidatorConfig::Config,
        /// The time of last reconfiguration invoked by this validator
        /// in microseconds
        last_config_update_time: u64,
    }

    /// Enables a scheme that restricts the DijetsSystem config
    /// in DijetsConfig from being modified by any other module.  Only
    /// code in this module can get a reference to the ModifyConfigCapability<DijetsSystem>,
    /// which is required by `DijetsConfig::set_with_capability_and_reconfigure` to
    /// modify the DijetsSystem config. This is only needed by `update_config_and_reconfigure`.
    /// Only Dijets root can add or remove a validator from the validator set, so the
    /// capability is not needed for access control in those functions.
    struct CapabilityHolder has key {
        /// Holds a capability returned by `DijetsConfig::publish_new_config_and_get_capability`
        /// which is called in `initialize_validator_set`.
        cap: ModifyConfigCapability<DijetsSystem>,
    }

    /// The DijetsSystem struct stores the validator set and crypto scheme in
    /// DijetsConfig. The DijetsSystem struct is stored by DijetsConfig, which publishes a
    /// DijetsConfig<DijetsSystem> resource.
    struct DijetsSystem has copy, drop, store {
        /// The current consensus crypto scheme.
        scheme: u8,
        /// The current validator set.
        validators: vector<ValidatorInfo>,
    }
    spec DijetsSystem {
        /// Members of `validators` vector (the validator set) have unique addresses.
        invariant
            forall i in 0..len(validators), j in 0..len(validators):
                validators[i].addr == validators[j].addr ==> i == j;
    }

    /// The `CapabilityHolder` resource was not in the required state
    const ECAPABILITY_HOLDER: u64 = 0;
    /// Tried to add a validator with an invalid state to the validator set
    const EINVALID_PROSPECTIVE_VALIDATOR: u64 = 1;
    /// Tried to add a validator to the validator set that was already in it
    const EALREADY_A_VALIDATOR: u64 = 2;
    /// An operation was attempted on an address not in the vaidator set
    const ENOT_AN_ACTIVE_VALIDATOR: u64 = 3;
    /// The validator operator is not the operator for the specified validator
    const EINVALID_TRANSACTION_SENDER: u64 = 4;
    /// An out of bounds index for the validator set was encountered
    const EVALIDATOR_INDEX: u64 = 5;
    /// Rate limited when trying to update config
    const ECONFIG_UPDATE_RATE_LIMITED: u64 = 6;
    /// Validator set already at maximum allowed size
    const EMAX_VALIDATORS: u64 = 7;
    /// Validator config update time overflows
    const ECONFIG_UPDATE_TIME_OVERFLOWS: u64 = 8;

    /// Number of microseconds in 5 minutes
    const FIVE_MINUTES: u64 = 300000000;

    /// The maximum number of allowed validators in the validator set
    const MAX_VALIDATORS: u64 = 256;

    /// The largest possible u64 value
    const MAX_U64: u64 = 18446744073709551615;

    ///////////////////////////////////////////////////////////////////////////
    // Setup methods
    ///////////////////////////////////////////////////////////////////////////


    /// Publishes the DijetsConfig for the DijetsSystem struct, which contains the current
    /// validator set. Also publishes the `CapabilityHolder` with the
    /// ModifyConfigCapability<DijetsSystem> returned by the publish function, which allows
    /// code in this module to change DijetsSystem config (including the validator set).
    /// Must be invoked by the Dijets root a single time in Genesis.
    public fun initialize_validator_set(
        dr_account: &signer,
    ) {
        DijetsTimestamp::assert_genesis();
        Roles::assert_dijets_root(dr_account);

        let cap = DijetsConfig::publish_new_config_and_get_capability<DijetsSystem>(
            dr_account,
            DijetsSystem {
                scheme: 0,
                validators: Vector::empty(),
            },
        );
        assert(
            !exists<CapabilityHolder>(@DijetsRoot),
            Errors::already_published(ECAPABILITY_HOLDER)
        );
        move_to(dr_account, CapabilityHolder { cap })
    }
    spec initialize_validator_set {
        modifies global<DijetsConfig::DijetsConfig<DijetsSystem>>(@DijetsRoot);
        include DijetsTimestamp::AbortsIfNotGenesis;
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};
        let dr_addr = Signer::spec_address_of(dr_account);
        // TODO: The next two aborts_if's are not independent. Perhaps they can be
        // simplified.
        aborts_if DijetsConfig::spec_is_published<DijetsSystem>() with Errors::ALREADY_PUBLISHED;
        aborts_if exists<CapabilityHolder>(dr_addr) with Errors::ALREADY_PUBLISHED;
        ensures exists<CapabilityHolder>(dr_addr);
        ensures DijetsConfig::spec_is_published<DijetsSystem>();
        ensures len(spec_get_validators()) == 0;
    }

    /// Copies a DijetsSystem struct into the DijetsConfig<DijetsSystem> resource
    /// Called by the add, remove, and update functions.
    fun set_dijets_system_config(value: DijetsSystem) acquires CapabilityHolder {
        DijetsTimestamp::assert_operating();
        assert(
            exists<CapabilityHolder>(@DijetsRoot),
            Errors::not_published(ECAPABILITY_HOLDER)
        );
        // Updates the DijetsConfig<DijetsSystem> and emits a reconfigure event.
        DijetsConfig::set_with_capability_and_reconfigure<DijetsSystem>(
            &borrow_global<CapabilityHolder>(@DijetsRoot).cap,
            value
        )
    }
    spec set_dijets_system_config {
        pragma opaque;
        modifies global<DijetsConfig::DijetsConfig<DijetsSystem>>(@DijetsRoot);
        modifies global<DijetsConfig::Configuration>(@DijetsRoot);
        include DijetsTimestamp::AbortsIfNotOperating;
        include DijetsConfig::ReconfigureAbortsIf;
        /// `payload` is the only field of DijetsConfig, so next completely specifies it.
        ensures global<DijetsConfig::DijetsConfig<DijetsSystem>>(@DijetsRoot).payload == value;
        include DijetsConfig::ReconfigureEmits;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Methods operating the Validator Set config callable by the dijets root account
    ///////////////////////////////////////////////////////////////////////////

    /// Adds a new validator to the validator set.
    public fun add_validator(
        dr_account: &signer,
        validator_addr: address
    ) acquires CapabilityHolder {

        DijetsTimestamp::assert_operating();
        Roles::assert_dijets_root(dr_account);
        // A prospective validator must have a validator config resource
        assert(ValidatorConfig::is_valid(validator_addr), Errors::invalid_argument(EINVALID_PROSPECTIVE_VALIDATOR));

        // Bound the validator set size
        assert(
            validator_set_size() < MAX_VALIDATORS,
            Errors::limit_exceeded(EMAX_VALIDATORS)
        );

        let dijets_system_config = get_dijets_system_config();

        // Ensure that this address is not already a validator
        assert(
            !is_validator_(validator_addr, &dijets_system_config.validators),
            Errors::invalid_argument(EALREADY_A_VALIDATOR)
        );

        // it is guaranteed that the config is non-empty
        let config = ValidatorConfig::get_config(validator_addr);
        Vector::push_back(&mut dijets_system_config.validators, ValidatorInfo {
            addr: validator_addr,
            config, // copy the config over to ValidatorSet
            consensus_voting_power: 1,
            last_config_update_time: DijetsTimestamp::now_microseconds(),
        });

        set_dijets_system_config(dijets_system_config);
    }
    spec add_validator {
        modifies global<DijetsConfig::DijetsConfig<DijetsSystem>>(@DijetsRoot);
        include AddValidatorAbortsIf;
        include AddValidatorEnsures;
        include DijetsConfig::ReconfigureEmits;
    }
    spec schema AddValidatorAbortsIf {
        dr_account: signer;
        validator_addr: address;
        aborts_if validator_set_size() >= MAX_VALIDATORS with Errors::LIMIT_EXCEEDED;
        include DijetsTimestamp::AbortsIfNotOperating;
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};
        include DijetsConfig::ReconfigureAbortsIf;
        aborts_if !ValidatorConfig::is_valid(validator_addr) with Errors::INVALID_ARGUMENT;
        aborts_if spec_is_validator(validator_addr) with Errors::INVALID_ARGUMENT;
    }
    spec schema AddValidatorEnsures {
        validator_addr: address;
        /// DIP-6 property: validator has validator role. The code does not check this explicitly,
        /// but it is implied by the `assert ValidatorConfig::is_valid`, since there
        /// is an invariant (in ValidatorConfig) that a an address with a published ValidatorConfig has
        /// a ValidatorRole
        ensures Roles::spec_has_validator_role_addr(validator_addr);
        ensures ValidatorConfig::is_valid(validator_addr);
        ensures spec_is_validator(validator_addr);
        let vs = spec_get_validators();
        let post post_vs = spec_get_validators();
        ensures Vector::eq_push_back(post_vs,
                                     vs,
                                     ValidatorInfo {
                                         addr: validator_addr,
                                         config: ValidatorConfig::spec_get_config(validator_addr),
                                         consensus_voting_power: 1,
                                         last_config_update_time: DijetsTimestamp::spec_now_microseconds(),
                                      }
                                   );
    }


    /// Removes a validator, aborts unless called by dijets root account
    public fun remove_validator(
        dr_account: &signer,
        validator_addr: address
    ) acquires CapabilityHolder {
        DijetsTimestamp::assert_operating();
        Roles::assert_dijets_root(dr_account);
        let dijets_system_config = get_dijets_system_config();
        // Ensure that this address is an active validator
        let to_remove_index_vec = get_validator_index_(&dijets_system_config.validators, validator_addr);
        assert(Option::is_some(&to_remove_index_vec), Errors::invalid_argument(ENOT_AN_ACTIVE_VALIDATOR));
        let to_remove_index = *Option::borrow(&to_remove_index_vec);
        // Remove corresponding ValidatorInfo from the validator set
        _  = Vector::swap_remove(&mut dijets_system_config.validators, to_remove_index);

        set_dijets_system_config(dijets_system_config);
    }
    spec remove_validator {
        modifies global<DijetsConfig::DijetsConfig<DijetsSystem>>(@DijetsRoot);
        include RemoveValidatorAbortsIf;
        include RemoveValidatorEnsures;
        include DijetsConfig::ReconfigureEmits;
    }
    spec schema RemoveValidatorAbortsIf {
        dr_account: signer;
        validator_addr: address;
        include Roles::AbortsIfNotDijetsRoot{account: dr_account};
        include DijetsTimestamp::AbortsIfNotOperating;
        include DijetsConfig::ReconfigureAbortsIf;
        aborts_if !spec_is_validator(validator_addr) with Errors::INVALID_ARGUMENT;
    }
    spec schema RemoveValidatorEnsures {
        validator_addr: address;
        let vs = spec_get_validators();
        let post post_vs = spec_get_validators();
        ensures forall vi in post_vs where vi.addr != validator_addr: exists ovi in vs: vi == ovi;
        /// Removed validator is no longer a validator.  Depends on no other entries for same address
        /// in validator_set
        ensures !spec_is_validator(validator_addr);
    }

    /// Copy the information from ValidatorConfig into the validator set.
    /// This function makes no changes to the size or the members of the set.
    /// If the config in the ValidatorSet changes, it stores the new DijetsSystem
    /// and emits a reconfigurationevent.
    public fun update_config_and_reconfigure(
        validator_operator_account: &signer,
        validator_addr: address,
    ) acquires CapabilityHolder {
        DijetsTimestamp::assert_operating();
        Roles::assert_validator_operator(validator_operator_account);
        assert(
            ValidatorConfig::get_operator(validator_addr) == Signer::address_of(validator_operator_account),
            Errors::invalid_argument(EINVALID_TRANSACTION_SENDER)
        );
        let dijets_system_config = get_dijets_system_config();
        let to_update_index_vec = get_validator_index_(&dijets_system_config.validators, validator_addr);
        assert(Option::is_some(&to_update_index_vec), Errors::invalid_argument(ENOT_AN_ACTIVE_VALIDATOR));
        let to_update_index = *Option::borrow(&to_update_index_vec);
        let is_validator_info_updated = update_ith_validator_info_(&mut dijets_system_config.validators, to_update_index);
        if (is_validator_info_updated) {
            let validator_info = Vector::borrow_mut(&mut dijets_system_config.validators, to_update_index);
            assert(
                validator_info.last_config_update_time <= MAX_U64 - FIVE_MINUTES,
                Errors::limit_exceeded(ECONFIG_UPDATE_TIME_OVERFLOWS)
            );
            assert(
                DijetsTimestamp::now_microseconds() > validator_info.last_config_update_time + FIVE_MINUTES,
                Errors::limit_exceeded(ECONFIG_UPDATE_RATE_LIMITED)
            );
            validator_info.last_config_update_time = DijetsTimestamp::now_microseconds();
            set_dijets_system_config(dijets_system_config);
        }
    }
    spec update_config_and_reconfigure {
        pragma opaque;
        modifies global<DijetsConfig::Configuration>(@DijetsRoot);
        modifies global<DijetsConfig::DijetsConfig<DijetsSystem>>(@DijetsRoot);
        include ValidatorConfig::AbortsIfGetOperator{addr: validator_addr};
        include UpdateConfigAndReconfigureAbortsIf;
        include UpdateConfigAndReconfigureEnsures;
        // The property below is not in `UpdateConfigAndReconfigureEnsures` because that is reused
        // with a different condition in the transaction script `set_validator_config_and_reconfigure`.
        // The validator set is not updated if: (1) `validator_addr` is not in the validator set, or
        // (2) the validator info would not change. The code only does a reconfiguration if the
        // validator set would change.  `ReconfigureAbortsIf` complains if the block time does not
        // advance, but block time only advances if there is a reconfiguration.
        let is_validator_info_updated =
            ValidatorConfig::is_valid(validator_addr) &&
            (exists v_info in spec_get_validators():
                v_info.addr == validator_addr
                && v_info.config != ValidatorConfig::spec_get_config(validator_addr));
        include is_validator_info_updated ==> DijetsConfig::ReconfigureAbortsIf;
        let validator_index =
            spec_index_of_validator(spec_get_validators(), validator_addr);
        let last_config_time = spec_get_validators()[validator_index].last_config_update_time;
        aborts_if is_validator_info_updated && last_config_time > MAX_U64 - FIVE_MINUTES
            with Errors::LIMIT_EXCEEDED;
        aborts_if is_validator_info_updated && DijetsTimestamp::spec_now_microseconds() <= last_config_time + FIVE_MINUTES
                with Errors::LIMIT_EXCEEDED;
        include UpdateConfigAndReconfigureEmits;
    }
    spec schema UpdateConfigAndReconfigureAbortsIf {
        validator_addr: address;
        validator_operator_account: signer;
        let validator_operator_addr = Signer::address_of(validator_operator_account);
        include DijetsTimestamp::AbortsIfNotOperating;
        /// Must abort if the signer does not have the ValidatorOperator role [[H15]][PERMISSION].
        include Roles::AbortsIfNotValidatorOperator{validator_operator_addr: validator_operator_addr};
        include ValidatorConfig::AbortsIfNoValidatorConfig{addr: validator_addr};
        aborts_if ValidatorConfig::get_operator(validator_addr) != validator_operator_addr
            with Errors::INVALID_ARGUMENT;
        aborts_if !spec_is_validator(validator_addr) with Errors::INVALID_ARGUMENT;
    }
    /// Does not change the length of the validator set, only changes ValidatorInfo
    /// for validator_addr, and doesn't change any addresses.
    spec schema UpdateConfigAndReconfigureEnsures {
        validator_addr: address;
        let vs = spec_get_validators();
        let post post_vs = spec_get_validators();
        ensures len(post_vs) == len(vs);
        /// No addresses change in the validator set
        ensures forall i in 0..len(vs): post_vs[i].addr == vs[i].addr;
        /// If the `ValidatorInfo` address is not the one we're changing, the info does not change.
        ensures forall i in 0..len(vs) where vs[i].addr != validator_addr:
                         post_vs[i] == vs[i];
        /// It updates the correct entry in the correct way
        ensures forall i in 0..len(vs): post_vs[i].config == vs[i].config ||
                    (vs[i].addr == validator_addr &&
                     post_vs[i].config == ValidatorConfig::get_config(validator_addr));
        /// DIP-6 property
        ensures Roles::spec_has_validator_role_addr(validator_addr);
    }
    spec schema UpdateConfigAndReconfigureEmits {
        validator_addr: address;
        let is_validator_info_updated =
            ValidatorConfig::is_valid(validator_addr) &&
            (exists v_info in spec_get_validators():
                v_info.addr == validator_addr
                && v_info.config != ValidatorConfig::spec_get_config(validator_addr));
        include is_validator_info_updated ==> DijetsConfig::ReconfigureEmits;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Publicly callable APIs: getters
    ///////////////////////////////////////////////////////////////////////////

    /// Get the DijetsSystem configuration from DijetsConfig
    public fun get_dijets_system_config(): DijetsSystem {
        DijetsConfig::get<DijetsSystem>()
    }
    spec get_dijets_system_config {
        pragma opaque;
        include DijetsConfig::AbortsIfNotPublished<DijetsSystem>;
        ensures result == DijetsConfig::get<DijetsSystem>();
    }

    /// Return true if `addr` is in the current validator set
    public fun is_validator(addr: address): bool {
        is_validator_(addr, &get_dijets_system_config().validators)
    }
    spec is_validator {
        pragma opaque;
        // TODO: Publication of DijetsConfig<DijetsSystem> in initialization
        // and persistence of configs implies that the next abort cannot
        // actually happen.
        include DijetsConfig::AbortsIfNotPublished<DijetsSystem>;
        ensures result == spec_is_validator(addr);
    }
    spec fun spec_is_validator(addr: address): bool {
        exists v in spec_get_validators(): v.addr == addr
    }

    /// Returns validator config. Aborts if `addr` is not in the validator set.
    public fun get_validator_config(addr: address): ValidatorConfig::Config {
        let dijets_system_config = get_dijets_system_config();
        let validator_index_vec = get_validator_index_(&dijets_system_config.validators, addr);
        assert(Option::is_some(&validator_index_vec), Errors::invalid_argument(ENOT_AN_ACTIVE_VALIDATOR));
        *&(Vector::borrow(&dijets_system_config.validators, *Option::borrow(&validator_index_vec))).config
    }
    spec get_validator_config {
        pragma opaque;
        include DijetsConfig::AbortsIfNotPublished<DijetsSystem>;
        aborts_if !spec_is_validator(addr) with Errors::INVALID_ARGUMENT;
        ensures
            exists info in DijetsConfig::get<DijetsSystem>().validators where info.addr == addr:
                result == info.config;
    }

    /// Return the size of the current validator set
    public fun validator_set_size(): u64 {
        Vector::length(&get_dijets_system_config().validators)
    }
    spec validator_set_size {
        pragma opaque;
        include DijetsConfig::AbortsIfNotPublished<DijetsSystem>;
        ensures result == len(spec_get_validators());
    }

    /// Get the `i`'th validator address in the validator set.
    public fun get_ith_validator_address(i: u64): address {
        assert(i < validator_set_size(), Errors::invalid_argument(EVALIDATOR_INDEX));
        Vector::borrow(&get_dijets_system_config().validators, i).addr
    }
    spec get_ith_validator_address {
        pragma opaque;
        include DijetsConfig::AbortsIfNotPublished<DijetsSystem>;
        aborts_if i >= len(spec_get_validators()) with Errors::INVALID_ARGUMENT;
        ensures result == spec_get_validators()[i].addr;
    }

    ///////////////////////////////////////////////////////////////////////////
    // Private functions
    ///////////////////////////////////////////////////////////////////////////

    /// Get the index of the validator by address in the `validators` vector
    /// It has a loop, so there are spec blocks in the code to assert loop invariants.
    fun get_validator_index_(validators: &vector<ValidatorInfo>, addr: address): Option<u64> {
        let size = Vector::length(validators);
        let i = 0;
        while ({
            spec {
                invariant i <= size;
                invariant forall j in 0..i: validators[j].addr != addr;
            };
            (i < size)
        })
        {
            let validator_info_ref = Vector::borrow(validators, i);
            if (validator_info_ref.addr == addr) {
                spec {
                    assert validators[i].addr == addr;
                };
                return Option::some(i)
            };
            i = i + 1;
        };
        spec {
            assert i == size;
            assert forall j in 0..size: validators[j].addr != addr;
        };
        return Option::none()
    }
    spec get_validator_index_ {
        pragma opaque;
        aborts_if false;
        let size = len(validators);
        /// If `addr` is not in validator set, returns none.
        ensures (forall i in 0..size: validators[i].addr != addr) ==> Option::is_none(result);
        /// If `addr` is in validator set, return the least index of an entry with that address.
        /// The data invariant associated with the DijetsSystem.validators that implies
        /// that there is exactly one such address.
        ensures
            (exists i in 0..size: validators[i].addr == addr) ==>
                Option::is_some(result)
                && {
                        let at = Option::borrow(result);
                        at == spec_index_of_validator(validators, addr)
                    };
    }

    /// Updates *i*th validator info, if nothing changed, return false.
    /// This function never aborts.
    fun update_ith_validator_info_(validators: &mut vector<ValidatorInfo>, i: u64): bool {
        let size = Vector::length(validators);
        // This provably cannot happen, but left it here for safety.
        if (i >= size) {
            return false
        };
        let validator_info = Vector::borrow_mut(validators, i);
        // "is_valid" below should always hold based on a global invariant later
        // in the file (which proves if we comment out some other specifications),
        // but it is left here for safety.
        if (!ValidatorConfig::is_valid(validator_info.addr)) {
            return false
        };
        let new_validator_config = ValidatorConfig::get_config(validator_info.addr);
        // check if information is the same
        let config_ref = &mut validator_info.config;
        if (config_ref == &new_validator_config) {
            return false
        };
        *config_ref = new_validator_config;
        true
    }
    spec update_ith_validator_info_ {
        pragma opaque;
        aborts_if false;
        let new_validator_config = ValidatorConfig::spec_get_config(validators[i].addr);
        /// Prover is able to prove this because get_validator_index_ ensures it
        /// in calling context.
        requires 0 <= i && i < len(validators);
        /// Somewhat simplified from the code because of properties guaranteed
        /// by the calling context.
        ensures
            result ==
                (ValidatorConfig::is_valid(validators[i].addr) &&
                 new_validator_config != old(validators[i].config));
        /// It only updates validators at index `i`, and updates the
        /// `config` field to `new_validator_config`.
        ensures
            result ==>
                validators == update(
                    old(validators),
                    i,
                    update_field(old(validators[i]), config, new_validator_config)
                );
        /// Does not change validators if result is false
        ensures !result ==> validators == old(validators);
        /// Updates the ith validator entry (and nothing else), as appropriate.
        ensures validators == update(old(validators), i, validators[i]);
        /// Needed these assertions to make "consensus voting power is always 1" invariant
        /// prove (not sure why).
        requires forall i1 in 0..len(spec_get_validators()):
           spec_get_validators()[i1].consensus_voting_power == 1;
        ensures forall i1 in 0..len(spec_get_validators()):
           spec_get_validators()[i1].consensus_voting_power == 1;
    }

    /// Private function checks for membership of `addr` in validator set.
    fun is_validator_(addr: address, validators_vec_ref: &vector<ValidatorInfo>): bool {
        Option::is_some(&get_validator_index_(validators_vec_ref, addr))
    }
    spec is_validator_ {
        pragma opaque;
        aborts_if false;
        ensures result == (exists v in validators_vec_ref: v.addr == addr);
    }

    // =================================================================
    // Module Specification

    spec module {} // Switch to module documentation context

    /// # Initialization
    spec module {
        /// After genesis, the `DijetsSystem` configuration is published, as well as the capability
        /// which grants the right to modify it to certain functions in this module.
        invariant DijetsTimestamp::is_operating() ==>
            DijetsConfig::spec_is_published<DijetsSystem>() &&
            exists<CapabilityHolder>(@DijetsRoot);
    }

    /// # Access Control

    /// Access control requirements for validator set are a bit more complicated than
    /// many parts of the framework because of `update_config_and_reconfigure`.
    /// That function updates the validator info (e.g., the network address) for a
    /// particular Validator Owner, but only if the signer is the Operator for that owner.
    /// Therefore, we must ensure that the information for other validators in the
    /// validator set are not changed, which is specified locally for
    /// `update_config_and_reconfigure`.

    spec module {
       /// The permission "{Add, Remove} Validator" is granted to DijetsRoot [[H14]][PERMISSION].
       apply Roles::AbortsIfNotDijetsRoot{account: dr_account} to add_validator, remove_validator;
    }

    spec schema ValidatorSetConfigRemainsSame {
        ensures spec_get_validators() == old(spec_get_validators());
    }
    spec module {
        /// Only {add, remove} validator [[H14]][PERMISSION] and update_config_and_reconfigure
        /// [[H15]][PERMISSION] may change the set of validators in the configuration.
        /// `set_dijets_system_config` is a private function which is only called by other
        /// functions in the "except" list. `initialize_validator_set` is only called in
        /// Genesis.
        apply ValidatorSetConfigRemainsSame to *, *<T>
           except add_validator, remove_validator, update_config_and_reconfigure,
               initialize_validator_set, set_dijets_system_config;
    }

    /// # Helper Functions

    /// Fetches the currently published validator set from the published DijetsConfig<DijetsSystem>
    /// resource.
    spec fun spec_get_validators(): vector<ValidatorInfo> {
        DijetsConfig::get<DijetsSystem>().validators
    }

    spec fun spec_index_of_validator(validators: vector<ValidatorInfo>, addr: address): u64 {
        choose min i in range(validators) where validators[i].addr == addr
    }

    spec module {

       /// Every validator has a published ValidatorConfig whose config option is "some"
       /// (meaning of ValidatorConfig::is_valid).
       /// > Unfortunately, this times out for unknown reasons (it doesn't seem to be hard),
       /// so it is deactivated.
       /// The Prover can prove it if the uniqueness invariant for the DijetsSystem resource
       /// is commented out, along with aborts for update_config_and_reconfigure and everything
       /// else that breaks (e.g., there is an ensures in remove_validator that has to be
       /// commented out)
       invariant [deactivated, global] forall i1 in 0..len(spec_get_validators()):
           ValidatorConfig::is_valid(spec_get_validators()[i1].addr);

       /// Every validator in the validator set has a validator role.
       /// > Note: Verification of DijetsSystem seems to be very sensitive, and will
       /// often time out after small changes.  Disabling this property
       /// (with [deactivate, global]) is sometimes a quick temporary fix.
       invariant forall i1 in 0..len(spec_get_validators()):
           Roles::spec_has_validator_role_addr(spec_get_validators()[i1].addr);

       /// `Consensus_voting_power` is always 1. In future implementations, this
       /// field may have different values in which case this property will have to
       /// change. It's here currently because and accidental or illicit change
       /// to the voting power of a validator could defeat the Byzantine fault tolerance
       /// of DijetsBFT.
       invariant forall i1 in 0..len(spec_get_validators()):
           spec_get_validators()[i1].consensus_voting_power == 1;

    }
}
