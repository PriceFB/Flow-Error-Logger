/**
 * Extension point for reacting to newly created Flow error logs (e.g. send an
 * email, post to Slack, publish a Platform Event). Implement this interface and
 * register your class so consumers can add notifications without editing the
 * core logger. The core package ships a no-op default (FlowErrorNotifierNoOp)
 * and never hardcodes any endpoint.
 */
public interface FlowErrorNotifier {
    /**
     * Called after logs are successfully inserted.
     * @param logs The Flow_Error_Log__c records that were just created.
     */
    void notify(List<Flow_Error_Log__c> logs);
}
