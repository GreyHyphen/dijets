/// Module managing Dijets ID.
module DijetsFramework::DijetsId {
    use Std::Event::{Self, EventHandle};
    use DijetsFramework::Roles;
    use Std::Errors;
    use Std::Signer;
    use Std::Vector;

    /// This resource holds an entity's domain names needed to send and receive payments using dijets IDs.
    struct DijetsIdDomains has key {
        /// The list of domain names owned by this parent vasp account
        domains: vector<DijetsIdDomain>,
    }
    spec DijetsIdDomains {
        /// All `DijetsIdDomain`s stored in the `DijetsIdDomains` resource are no more than 63 characters long.
        invariant forall i in 0..len(domains): len(domains[i].domain) <= DOMAIN_LENGTH;
        /// The list of `DijetsIdDomain`s are a set
        invariant forall i in 0..len(domains):
            forall j in i + 1..len(domains): domains[i] != domains[j];
    }

    /// Struct to store the limit on-chain
    struct DijetsIdDomain has drop, store, copy {
        domain: vector<u8>, // UTF-8 encoded and 63 characters
    }
    spec DijetsIdDomain {
        /// All `DijetsIdDomain`s must be no more than 63 characters long.
        invariant len(domain) <= DOMAIN_LENGTH;
    }

    struct DijetsIdDomainManager has key {
        /// Event handle for `domains` added or removed events. Emitted every time a domain is added
        /// or removed to `domains`
        dijets_id_domain_events: EventHandle<DijetsIdDomainEvent>,
    }

    struct DijetsIdDomainEvent has drop, store {
        /// Whether a domain was added or removed
        removed: bool,
        /// Dijets ID Domain string of the account
        domain: DijetsIdDomain,
        /// On-chain account address
        address: address,
    }

    const DOMAIN_LENGTH: u64 = 63;

    // Error codes
    /// DijetsIdDomains resource is not or already published.
    const EDIJETS_ID_DOMAIN: u64 = 0;
    /// DijetsIdDomainManager resource is not or already published.
    const EDIJETS_ID_DOMAIN_MANAGER: u64 = 1;
    /// DijetsID domain was not found
    const EDOMAIN_NOT_FOUND: u64 = 2;
    /// DijetsID domain already exists
    const EDOMAIN_ALREADY_EXISTS: u64 = 3;
    /// DijetsIdDomains resource was not published for a VASP account
    const EDIJETS_ID_DOMAINS_NOT_PUBLISHED: u64 = 4;
    /// Invalid domain for DijetsIdDomain
    const EINVALID_DIJETS_ID_DOMAIN: u64 = 5;

    fun create_dijets_id_domain(domain: vector<u8>): DijetsIdDomain {
        assert(Vector::length(&domain) <= DOMAIN_LENGTH, Errors::invalid_argument(EINVALID_DIJETS_ID_DOMAIN));
        DijetsIdDomain{ domain }
    }
    spec create_dijets_id_domain {
        include CreateDijetsIdDomainAbortsIf;
        ensures result == DijetsIdDomain { domain };
    }
    spec schema CreateDijetsIdDomainAbortsIf {
        domain: vector<u8>;
        aborts_if Vector::length(domain) > DOMAIN_LENGTH with Errors::INVALID_ARGUMENT;
    }

    /// Publish a `DijetsIdDomains` resource under `created` with an empty `domains`.
    /// Before sending or receiving any payments using Dijets IDs, the Treasury Compliance account must send
    /// a transaction that invokes `add_domain_id` to set the `domains` field with a valid domain
    public fun publish_dijets_id_domains(
        vasp_account: &signer,
    ) {
        Roles::assert_parent_vasp_role(vasp_account);
        assert(
            !exists<DijetsIdDomains>(Signer::address_of(vasp_account)),
            Errors::already_published(EDIJETS_ID_DOMAIN)
        );
        move_to(vasp_account, DijetsIdDomains {
            domains: Vector::empty(),
        })
    }
    spec publish_dijets_id_domains {
        let vasp_addr = Signer::spec_address_of(vasp_account);
        include Roles::AbortsIfNotParentVasp{account: vasp_account};
        include PublishDijetsIdDomainsAbortsIf;
        include PublishDijetsIdDomainsEnsures;
    }
    spec schema PublishDijetsIdDomainsAbortsIf {
        vasp_addr: address;
        aborts_if has_dijets_id_domains(vasp_addr) with Errors::ALREADY_PUBLISHED;
    }
    spec schema PublishDijetsIdDomainsEnsures {
        vasp_addr: address;
        ensures exists<DijetsIdDomains>(vasp_addr);
        ensures Vector::is_empty(global<DijetsIdDomains>(vasp_addr).domains);
    }

    public fun has_dijets_id_domains(addr: address): bool {
        exists<DijetsIdDomains>(addr)
    }
    spec has_dijets_id_domains {
        aborts_if false;
        ensures result == exists<DijetsIdDomains>(addr);
    }

    /// Publish a `DijetsIdDomainManager` resource under `tc_account` with an empty `dijets_id_domain_events`.
    /// When Treasury Compliance account sends a transaction that invokes either `add_dijets_id_domain` or
    /// `remove_dijets_id_domain`, a `DijetsIdDomainEvent` is emitted and added to `dijets_id_domain_events`.
    public fun publish_dijets_id_domain_manager(
        tc_account : &signer,
    ) {
        Roles::assert_treasury_compliance(tc_account);
        assert(
            !exists<DijetsIdDomainManager>(Signer::address_of(tc_account)),
            Errors::already_published(EDIJETS_ID_DOMAIN_MANAGER)
        );
        move_to(
            tc_account,
            DijetsIdDomainManager {
                dijets_id_domain_events: Event::new_event_handle<DijetsIdDomainEvent>(tc_account),
            }
        );
    }
    spec publish_dijets_id_domain_manager {
        include Roles::AbortsIfNotTreasuryCompliance{account: tc_account};
        aborts_if tc_domain_manager_exists() with Errors::ALREADY_PUBLISHED;
        ensures exists<DijetsIdDomainManager>(Signer::spec_address_of(tc_account));
        modifies global<DijetsIdDomainManager>(Signer::spec_address_of(tc_account));
    }

    /// Add a DijetsIdDomain to a parent VASP's DijetsIdDomains resource.
    /// When updating DijetsIdDomains, a simple duplicate domain check is done.
    /// However, since domains are case insensitive, it is possible by error that two same domains in
    /// different lowercase and uppercase format gets added.
    public fun add_dijets_id_domain(
        tc_account: &signer,
        address: address,
        domain: vector<u8>,
    ) acquires DijetsIdDomainManager, DijetsIdDomains {
        Roles::assert_treasury_compliance(tc_account);
        assert(tc_domain_manager_exists(), Errors::not_published(EDIJETS_ID_DOMAIN_MANAGER));
        assert(
            exists<DijetsIdDomains>(address),
            Errors::not_published(EDIJETS_ID_DOMAINS_NOT_PUBLISHED)
        );

        let account_domains = borrow_global_mut<DijetsIdDomains>(address);
        let dijets_id_domain = create_dijets_id_domain(domain);

        assert(
            !Vector::contains(&account_domains.domains, &dijets_id_domain),
            Errors::invalid_argument(EDOMAIN_ALREADY_EXISTS)
        );

        Vector::push_back(&mut account_domains.domains, copy dijets_id_domain);

        Event::emit_event(
            &mut borrow_global_mut<DijetsIdDomainManager>(@TreasuryCompliance).dijets_id_domain_events,
            DijetsIdDomainEvent {
                removed: false,
                domain: dijets_id_domain,
                address,
            },
        );
    }
    spec add_dijets_id_domain {
        include AddDijetsIdDomainAbortsIf;
        include AddDijetsIdDomainEnsures;
        include AddDijetsIdDomainEmits;
    }
    spec schema AddDijetsIdDomainAbortsIf {
        tc_account: signer;
        address: address;
        domain: vector<u8>;
        let domains = global<DijetsIdDomains>(address).domains;
        include Roles::AbortsIfNotTreasuryCompliance{account: tc_account};
        include CreateDijetsIdDomainAbortsIf;
        aborts_if !exists<DijetsIdDomains>(address) with Errors::NOT_PUBLISHED;
        aborts_if !tc_domain_manager_exists() with Errors::NOT_PUBLISHED;
        aborts_if contains(domains, DijetsIdDomain { domain }) with Errors::INVALID_ARGUMENT;
    }
    spec schema AddDijetsIdDomainEnsures {
        address: address;
        domain: vector<u8>;
        let post domains = global<DijetsIdDomains>(address).domains;
        ensures contains(domains, DijetsIdDomain { domain });
    }
    spec schema AddDijetsIdDomainEmits {
        address: address;
        domain: vector<u8>;
        let handle = global<DijetsIdDomainManager>(@TreasuryCompliance).dijets_id_domain_events;
        let msg = DijetsIdDomainEvent {
            removed: false,
            domain: DijetsIdDomain { domain },
            address,
        };
        emits msg to handle;
    }

    /// Remove a DijetsIdDomain from a parent VASP's DijetsIdDomains resource.
    public fun remove_dijets_id_domain(
        tc_account: &signer,
        address: address,
        domain: vector<u8>,
    ) acquires DijetsIdDomainManager, DijetsIdDomains {
        Roles::assert_treasury_compliance(tc_account);
        assert(tc_domain_manager_exists(), Errors::not_published(EDIJETS_ID_DOMAIN_MANAGER));
        assert(
            exists<DijetsIdDomains>(address),
            Errors::not_published(EDIJETS_ID_DOMAINS_NOT_PUBLISHED)
        );

        let account_domains = borrow_global_mut<DijetsIdDomains>(address);
        let dijets_id_domain = create_dijets_id_domain(domain);

        let (has, index) = Vector::index_of(&account_domains.domains, &dijets_id_domain);
        if (has) {
            Vector::remove(&mut account_domains.domains, index);
        } else {
            abort Errors::invalid_argument(EDOMAIN_NOT_FOUND)
        };

        Event::emit_event(
            &mut borrow_global_mut<DijetsIdDomainManager>(@TreasuryCompliance).dijets_id_domain_events,
            DijetsIdDomainEvent {
                removed: true,
                domain: dijets_id_domain,
                address: address,
            },
        );
    }
    spec remove_dijets_id_domain {
        include RemoveDijetsIdDomainAbortsIf;
        include RemoveDijetsIdDomainEnsures;
        include RemoveDijetsIdDomainEmits;
    }
    spec schema RemoveDijetsIdDomainAbortsIf {
        tc_account: signer;
        address: address;
        domain: vector<u8>;
        let domains = global<DijetsIdDomains>(address).domains;
        include Roles::AbortsIfNotTreasuryCompliance{account: tc_account};
        include CreateDijetsIdDomainAbortsIf;
        aborts_if !exists<DijetsIdDomains>(address) with Errors::NOT_PUBLISHED;
        aborts_if !tc_domain_manager_exists() with Errors::NOT_PUBLISHED;
        aborts_if !contains(domains, DijetsIdDomain { domain }) with Errors::INVALID_ARGUMENT;
    }
    spec schema RemoveDijetsIdDomainEnsures {
        address: address;
        domain: vector<u8>;
        let post domains = global<DijetsIdDomains>(address).domains;
        ensures !contains(domains, DijetsIdDomain { domain });
    }
    spec schema RemoveDijetsIdDomainEmits {
        tc_account: signer;
        address: address;
        domain: vector<u8>;
        let handle = global<DijetsIdDomainManager>(@TreasuryCompliance).dijets_id_domain_events;
        let msg = DijetsIdDomainEvent {
            removed: true,
            domain: DijetsIdDomain { domain },
            address,
        };
        emits msg to handle;
    }

    public fun has_dijets_id_domain(addr: address, domain: vector<u8>): bool acquires DijetsIdDomains {
        assert(
            exists<DijetsIdDomains>(addr),
            Errors::not_published(EDIJETS_ID_DOMAINS_NOT_PUBLISHED)
        );
        let account_domains = borrow_global<DijetsIdDomains>(addr);
        let dijets_id_domain = create_dijets_id_domain(domain);
        Vector::contains(&account_domains.domains, &dijets_id_domain)
    }
    spec has_dijets_id_domain {
        include HasDijetsIdDomainAbortsIf;
        let id_domain = DijetsIdDomain { domain };
        ensures result == contains(global<DijetsIdDomains>(addr).domains, id_domain);
    }
    spec schema HasDijetsIdDomainAbortsIf {
        addr: address;
        domain: vector<u8>;
        include CreateDijetsIdDomainAbortsIf;
        aborts_if !exists<DijetsIdDomains>(addr) with Errors::NOT_PUBLISHED;
    }

    public fun tc_domain_manager_exists(): bool {
        exists<DijetsIdDomainManager>(@TreasuryCompliance)
    }
    spec tc_domain_manager_exists {
        aborts_if false;
        ensures result == exists<DijetsIdDomainManager>(@TreasuryCompliance);
    }
}
