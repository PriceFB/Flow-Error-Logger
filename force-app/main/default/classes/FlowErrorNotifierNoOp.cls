/**
 * Default FlowErrorNotifier implementation. Intentionally does nothing so the
 * package works out of the box without any external configuration. Replace it
 * with your own implementation (email, Slack, Platform Event, etc.) to enable
 * notifications. See the README "Extension points" section.
 */
public with sharing class FlowErrorNotifierNoOp implements FlowErrorNotifier {
  public void notify(List<Flow_Error_Log__c> logs) {
    // No-op by design. Consumers provide their own notifier implementation.
    return;
  }
}
