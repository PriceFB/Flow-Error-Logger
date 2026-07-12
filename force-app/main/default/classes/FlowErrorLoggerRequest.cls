/**
 * Data container for a single Flow error to be logged. Each instance maps to one
 * Flow_Error_Log__c record. Exposed to Flow Builder via @InvocableVariable so any
 * fault path can pass the details it has available.
 */
public with sharing class FlowErrorLoggerRequest {
  @InvocableVariable(
    label='Flow API Name'
    description='API name of the Flow that hit the fault path.'
    required=true
  )
  public String flowApiName;

  @InvocableVariable(
    label='Error Message'
    description='The captured fault message. Pass {!$Flow.FaultMessage}.'
    required=true
  )
  public String errorMessage;

  @InvocableVariable(
    label='Severity'
    description='Info, Warning, Error, or Critical. Defaults to Error when blank or invalid.'
  )
  public String severity;

  @InvocableVariable(
    label='Record Id'
    description='Optional Id of the record the Flow was operating on.'
  )
  public String recordId;

  @InvocableVariable(
    label='Flow Interview GUID'
    description='Optional Flow interview GUID for tracing a specific run.'
  )
  public String flowInterviewGuid;

  @InvocableVariable(
    label='Element Name'
    description='Optional name of the Flow element/step where the fault occurred.'
  )
  public String elementName;

  @InvocableVariable(
    label='Running User Id'
    description='Optional User Id running the Flow. Defaults to the current user.'
  )
  public Id runningUserId;

  @InvocableVariable(
    label='Context'
    description='Optional JSON/context payload for debugging.'
  )
  public String context;
}
