script {
    use DijetsFramework::DijetsSystem;
    fun main(dijets_root: signer) {
        {{#each addresses}}
        DijetsSystem::remove_validator(&dijets_root, @0x{{this}});
        {{/each}}
    }
}
