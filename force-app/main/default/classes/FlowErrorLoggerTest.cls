/**
 * Unit tests for FlowErrorLogger. Validates field mapping, bulk-safety,
 * severity/user defaults, truncation, non-throwing behavior on failure, and the
 * notifier extension point.
 */
@isTest
private class FlowErrorLoggerTest {
    private static FlowErrorLoggerRequest buildRequest() {
        FlowErrorLoggerRequest request = new FlowErrorLoggerRequest();
        request.flowApiName = 'Demo_Flow_Error_Logger';
        request.errorMessage = 'Something went wrong on the fault path.';
        request.severity = 'Warning';
        request.recordId = '001000000000001';
        request.flowInterviewGuid = 'GUID-12345';
        request.elementName = 'Get_Records';
        request.runningUserId = UserInfo.getUserId();
        request.context = '{"step":"demo"}';
        return request;
    }

    @isTest
    static void shouldInsertOneLogWithCorrectMapping_WhenSingleRequest() {
        FlowErrorLoggerRequest request = buildRequest();

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Assert.areEqual(1, createdIds.size(), 'Exactly one log should be created');

        Flow_Error_Log__c log = [
            SELECT Flow_API_Name__c, Error_Message__c, Severity__c, Record_Id__c,
                   Flow_Interview_Guid__c, Element_Name__c, Running_User__c, Context__c
            FROM Flow_Error_Log__c
            WHERE Id = :createdIds[0]
        ];
        Assert.areEqual(request.flowApiName, log.Flow_API_Name__c, 'Flow API name should map through');
        Assert.areEqual(request.errorMessage, log.Error_Message__c, 'Error message should map through');
        Assert.areEqual('Warning', log.Severity__c, 'Severity should map through');
        Assert.areEqual(request.recordId, log.Record_Id__c, 'Record Id should map through');
        Assert.areEqual(request.flowInterviewGuid, log.Flow_Interview_Guid__c, 'Interview GUID should map through');
        Assert.areEqual(request.elementName, log.Element_Name__c, 'Element name should map through');
        Assert.areEqual(UserInfo.getUserId(), log.Running_User__c, 'Running user should map through');
        Assert.areEqual(request.context, log.Context__c, 'Context should map through');
    }

    @isTest
    static void shouldInsertAllInSingleDml_WhenBulkRequest() {
        List<FlowErrorLoggerRequest> requests = new List<FlowErrorLoggerRequest>();
        for (Integer i = 0; i < 200; i++) {
            FlowErrorLoggerRequest request = buildRequest();
            request.errorMessage = 'Bulk error ' + i;
            requests.add(request);
        }

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        List<Id> createdIds = FlowErrorLogger.logErrors(requests);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(200, createdIds.size(), 'All 200 logs should be created');
        Assert.areEqual(1, dmlUsed, 'Bulk insert should use exactly one DML statement');
        Assert.areEqual(200, [SELECT COUNT() FROM Flow_Error_Log__c], 'All 200 records should exist');
    }

    @isTest
    static void shouldDefaultToError_WhenSeverityBlank() {
        FlowErrorLoggerRequest request = buildRequest();
        request.severity = '';

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Flow_Error_Log__c log = [SELECT Severity__c FROM Flow_Error_Log__c WHERE Id = :createdIds[0]];
        Assert.areEqual('Error', log.Severity__c, 'Blank severity should default to Error');
    }

    @isTest
    static void shouldDefaultToError_WhenSeverityInvalid() {
        FlowErrorLoggerRequest request = buildRequest();
        request.severity = 'NotARealSeverity';

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Flow_Error_Log__c log = [SELECT Severity__c FROM Flow_Error_Log__c WHERE Id = :createdIds[0]];
        Assert.areEqual('Error', log.Severity__c, 'Invalid severity should fall back to Error');
    }

    @isTest
    static void shouldNormalizeCase_WhenSeverityValidButLowercase() {
        FlowErrorLoggerRequest request = buildRequest();
        request.severity = 'critical';

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Flow_Error_Log__c log = [SELECT Severity__c FROM Flow_Error_Log__c WHERE Id = :createdIds[0]];
        Assert.areEqual('Critical', log.Severity__c, 'Lowercase severity should map to canonical picklist value');
    }

    @isTest
    static void shouldDefaultToCurrentUser_WhenRunningUserIdNull() {
        FlowErrorLoggerRequest request = buildRequest();
        request.runningUserId = null;

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Flow_Error_Log__c log = [SELECT Running_User__c FROM Flow_Error_Log__c WHERE Id = :createdIds[0]];
        Assert.areEqual(UserInfo.getUserId(), log.Running_User__c, 'Null running user should default to current user');
    }

    @isTest
    static void shouldTruncate_WhenTextExceedsFieldLength() {
        String oversized = 'a';
        while (oversized.length() < 40000) {
            oversized += oversized;
        }
        oversized = oversized.substring(0, 40000);

        FlowErrorLoggerRequest request = buildRequest();
        request.errorMessage = oversized;
        request.context = oversized;

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Assert.areEqual(1, createdIds.size(), 'Oversized input should be truncated, not throw');
        Flow_Error_Log__c log = [SELECT Error_Message__c, Context__c FROM Flow_Error_Log__c WHERE Id = :createdIds[0]];
        Assert.areEqual(32768, log.Error_Message__c.length(), 'Error message should be truncated to field length');
        Assert.areEqual(32768, log.Context__c.length(), 'Context should be truncated to field length');
    }

    @isTest
    static void shouldSwallowFailure_WhenInsertFails() {
        FlowErrorLoggerRequest request = buildRequest();
        request.runningUserId = '005000000000000';

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
        Test.stopTest();

        Assert.areEqual(0, createdIds.size(), 'A failed insert should return no Ids');
        Assert.areEqual(0, [SELECT COUNT() FROM Flow_Error_Log__c], 'No record should be persisted on failure');
    }

    @isTest
    static void shouldReturnEmpty_WhenRequestsNull() {
        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(null);
        Test.stopTest();

        Assert.areEqual(0, createdIds.size(), 'Null input should return an empty list');
    }

    @isTest
    static void shouldReturnEmpty_WhenRequestsEmpty() {
        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>());
        Test.stopTest();

        Assert.areEqual(0, createdIds.size(), 'Empty input should return an empty list');
    }

    @isTest
    static void shouldSkipNullElements_WhenListContainsNulls() {
        FlowErrorLoggerRequest request = buildRequest();

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(
            new List<FlowErrorLoggerRequest>{ null, request, null }
        );
        Test.stopTest();

        Assert.areEqual(1, createdIds.size(), 'Null elements should be skipped, valid one logged');
    }

    @isTest
    static void shouldReturnEmpty_WhenAllElementsNull() {
        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(
            new List<FlowErrorLoggerRequest>{ null, null }
        );
        Test.stopTest();

        Assert.areEqual(0, createdIds.size(), 'A list of only nulls should create nothing');
    }

    @isTest
    static void shouldInvokeNotifier_WhenLogsCreated() {
        RecordingNotifier recorder = new RecordingNotifier();
        FlowErrorLogger.notifier = recorder;

        Test.startTest();
        FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ buildRequest() });
        Test.stopTest();

        Assert.areEqual(1, recorder.notifiedLogs.size(), 'Notifier should receive the created log');
    }

    @isTest
    static void shouldSwallowNotifierException_WhenNotifierThrows() {
        FlowErrorLogger.notifier = new ThrowingNotifier();

        Test.startTest();
        List<Id> createdIds = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ buildRequest() });
        Test.stopTest();

        Assert.areEqual(1, createdIds.size(), 'A throwing notifier must not prevent logging or bubble up');
    }

    private class RecordingNotifier implements FlowErrorNotifier {
        public List<Flow_Error_Log__c> notifiedLogs = new List<Flow_Error_Log__c>();
        public void notify(List<Flow_Error_Log__c> logs) {
            notifiedLogs.addAll(logs);
        }
    }

    private class ThrowingNotifier implements FlowErrorNotifier {
        public void notify(List<Flow_Error_Log__c> logs) {
            throw new CalloutException('Simulated notifier failure');
        }
    }
}
