script {
    use DijetsFramework::DijetsTransactionPublishingOption;
    fun main(dijets_root: signer) {
        DijetsTransactionPublishingOption::halt_all_transactions(&dijets_root);
    }
}
