/**
 * Invocable entry point for logging Flow fault-path errors into Flow_Error_Log__c.
 *
 * Design guarantees:
 * - Bulk-safe: builds all records in memory and performs a single DML insert.
 * - Non-throwing: a logging failure is caught and swallowed so it never makes a
 *   calling Flow's failure worse.
 * - Defaults & validation: blank/invalid Severity falls back to 'Error'; a null
 *   Running User defaults to the current user; oversized text is truncated to fit.
 * - Sharing tradeoff: the class is `with sharing`, but the actual insert is
 *   delegated to a private `without sharing` inner class running in system mode so
 *   even low-privilege users can write a log. See the README design notes.
 */
public with sharing class FlowErrorLogger {
  private static final String DEFAULT_SEVERITY = 'Error';

  private static final Integer FLOW_API_NAME_MAX = Flow_Error_Log__c.Flow_API_Name__c.getDescribe()
    .getLength();
  private static final Integer ERROR_MESSAGE_MAX = Flow_Error_Log__c.Error_Message__c.getDescribe()
    .getLength();
  private static final Integer RECORD_ID_MAX = Flow_Error_Log__c.Record_Id__c.getDescribe()
    .getLength();
  private static final Integer INTERVIEW_GUID_MAX = Flow_Error_Log__c.Flow_Interview_Guid__c.getDescribe()
    .getLength();
  private static final Integer ELEMENT_NAME_MAX = Flow_Error_Log__c.Element_Name__c.getDescribe()
    .getLength();
  private static final Integer CONTEXT_MAX = Flow_Error_Log__c.Context__c.getDescribe()
    .getLength();

  private static Set<String> cachedSeverities;

  /**
   * Notifier invoked after logs are inserted. Defaults to a no-op; swap it for a
   * custom FlowErrorNotifier to enable email/Slack/Platform Event notifications.
   */
  @TestVisible
  private static FlowErrorNotifier notifier = new FlowErrorNotifierNoOp();

  /**
   * Creates a Flow_Error_Log__c record for each request. Safe to call from any
   * Flow fault path — it never throws back into the calling Flow.
   *
   * @param requests The errors to log, one record per request.
   * @return The Ids of the log records that were successfully created.
   * @example
   * List<Id> ids = FlowErrorLogger.logErrors(new List<FlowErrorLoggerRequest>{ request });
   */
  @InvocableMethod(
    label='Log Flow Error'
    description='Creates a Flow Error Log record from a Flow fault path. Never throws back into the calling Flow.'
    category='Flow Error Logger'
  )
  public static List<Id> logErrors(List<FlowErrorLoggerRequest> requests) {
    List<Id> createdIds = new List<Id>();
    if (requests == null || requests.isEmpty()) {
      return createdIds;
    }

    try {
      List<Flow_Error_Log__c> logs = new List<Flow_Error_Log__c>();
      for (FlowErrorLoggerRequest request : requests) {
        if (request == null) {
          continue;
        }
        logs.add(buildLog(request));
      }

      if (logs.isEmpty()) {
        return createdIds;
      }

      List<Database.SaveResult> results = new LogWriter().insertLogs(logs);
      List<Flow_Error_Log__c> insertedLogs = collectSuccesses(
        results,
        logs,
        createdIds
      );
      notifySafely(insertedLogs);
    } catch (Exception e) {
      // Logging must never worsen the caller's failure — swallow and move on.
      System.debug(
        LoggingLevel.ERROR,
        'FlowErrorLogger.logErrors failed: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
    }

    return createdIds;
  }

  /**
   * Maps a single request onto a Flow_Error_Log__c, applying defaults and truncation.
   * @param request The source request.
   * @return A populated, unsaved Flow_Error_Log__c.
   */
  private static Flow_Error_Log__c buildLog(FlowErrorLoggerRequest request) {
    return new Flow_Error_Log__c(
      Flow_API_Name__c = truncate(request.flowApiName, FLOW_API_NAME_MAX),
      Error_Message__c = truncate(request.errorMessage, ERROR_MESSAGE_MAX),
      Severity__c = resolveSeverity(request.severity),
      Record_Id__c = truncate(request.recordId, RECORD_ID_MAX),
      Flow_Interview_Guid__c = truncate(
        request.flowInterviewGuid,
        INTERVIEW_GUID_MAX
      ),
      Element_Name__c = truncate(request.elementName, ELEMENT_NAME_MAX),
      Running_User__c = request.runningUserId != null
        ? request.runningUserId
        : UserInfo.getUserId(),
      Context__c = truncate(request.context, CONTEXT_MAX)
    );
  }

  /**
   * Returns a valid, canonically-cased Severity picklist value, defaulting to
   * 'Error' when the supplied value is blank or not an allowed value.
   * @param severity The requested severity.
   * @return A valid Severity__c picklist value.
   */
  private static String resolveSeverity(String severity) {
    if (String.isBlank(severity)) {
      return DEFAULT_SEVERITY;
    }
    for (String validValue : validSeverities()) {
      if (validValue.equalsIgnoreCase(severity)) {
        return validValue;
      }
    }
    return DEFAULT_SEVERITY;
  }

  /**
   * Lazily builds and caches the set of valid Severity picklist values from the
   * field describe, so the allowed values stay in sync with the picklist.
   * @return The allowed Severity values.
   */
  private static Set<String> validSeverities() {
    if (cachedSeverities == null) {
      cachedSeverities = new Set<String>();
      for (
        Schema.PicklistEntry entry : Flow_Error_Log__c.Severity__c.getDescribe()
          .getPicklistValues()
      ) {
        cachedSeverities.add(entry.getValue());
      }
    }
    return cachedSeverities;
  }

  /**
   * Truncates a value to the field's maximum length to avoid STRING_TOO_LONG.
   * @param value The raw value.
   * @param maxLength The field's maximum length.
   * @return The value, trimmed to maxLength when necessary.
   */
  private static String truncate(String value, Integer maxLength) {
    if (String.isBlank(value)) {
      return value;
    }
    return value.length() > maxLength ? value.substring(0, maxLength) : value;
  }

  /**
   * Collects the Ids of successful inserts and returns the matching records.
   * @param results The DML save results, index-aligned with logs.
   * @param logs The records that were inserted.
   * @param createdIds Output collection; successful Ids are added here.
   * @return The records that were successfully inserted.
   */
  private static List<Flow_Error_Log__c> collectSuccesses(
    List<Database.SaveResult> results,
    List<Flow_Error_Log__c> logs,
    List<Id> createdIds
  ) {
    List<Flow_Error_Log__c> insertedLogs = new List<Flow_Error_Log__c>();
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        createdIds.add(results[i].getId());
        insertedLogs.add(logs[i]);
      } else {
        System.debug(
          LoggingLevel.ERROR,
          'FlowErrorLogger insert failed: ' + results[i].getErrors()
        );
      }
    }
    return insertedLogs;
  }

  /**
   * Invokes the configured notifier without letting a notifier failure throw.
   * @param insertedLogs The logs that were successfully created.
   */
  private static void notifySafely(List<Flow_Error_Log__c> insertedLogs) {
    if (insertedLogs == null || insertedLogs.isEmpty() || notifier == null) {
      return;
    }
    try {
      notifier.notify(insertedLogs);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'FlowErrorNotifier failed: ' + e.getMessage()
      );
    }
  }

  /**
   * Performs the log insert in system mode from a `without sharing` context so
   * that any user — regardless of sharing or FLS — can still write an error log.
   * Isolated here to keep elevated access scoped to the insert only.
   */
  private without sharing class LogWriter {
    public List<Database.SaveResult> insertLogs(List<Flow_Error_Log__c> logs) {
      return Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
    }
  }
}
