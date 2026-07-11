# Flow Error Logger

> A drop-in Salesforce package that captures Flow fault-path errors into a structured, queryable custom object — so your Flows stop failing silently.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v67.0-00A1E0.svg)](https://developer.salesforce.com)
[![Apex Coverage](https://img.shields.io/badge/Apex%20coverage-97%25-brightgreen.svg)](#tests)

## The problem

Salesforce Flows fail silently. When a fault path is hit, there's no standard, queryable, human-readable log. Teams discover failures late — usually from an angry user — and then spend time reproducing the issue with no breadcrumbs.

**Flow Error Logger** fixes this. It gives you:

- A standardized `Flow_Error_Log__c` object to store every captured failure.
- A bulk-safe, non-throwing **`Log Flow Error`** Invocable action you can call from any fault connector.
- An extension point for notifications (email, Slack, Platform Events) without editing the core.

## Screenshots

> Images live in [`docs/screenshots/`](./docs/screenshots). Add your own captures there.

| Log record | Demo flow |
|---|---|
| ![Flow Error Log record](./docs/screenshots/flow-error-log-record.png) | ![Demo flow fault path](./docs/screenshots/demo-flow.png) |

## Install

### Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) installed — verify with `sf --version`.
- Access to a Salesforce org you can deploy to: a **sandbox**, a **scratch org**, or a free [Developer Edition](https://developer.salesforce.com/signup) org. (Do **not** use a production org for a first try.)

### Option A — Deploy the source directly (recommended for a first try)

Copy‑paste friendly. Replace `myorg` with any alias you like — it's just a local nickname for your org.

```bash
# 1. Clone this repo and move into it
git clone https://github.com/PriceFB/Flow-Error-Logger.git
cd Flow-Error-Logger

# 2. Authorize YOUR OWN Salesforce org (opens a browser login)
#    Use --instance-url https://test.salesforce.com for a sandbox.
sf org login web --alias myorg

# 3. Deploy all the metadata (object, fields, tab, layout, Apex, flow, permission set)
sf project deploy start --source-dir force-app --target-org myorg

# 4. Grant yourself access to the object, fields, tab, and Apex
sf org assign permset --name Flow_Error_Logger_Admin --target-org myorg

# 5. (Optional) Open the org and find the "Flow Error Logs" tab
sf org open --target-org myorg
```

That's it — you can now add the **Log Flow Error** action to any Flow fault path (see below).

### Option B — Unlocked package (2GP)

Prefer a one-click install? Publish it once from a Dev Hub as an unlocked package, then install it by Id (or share the install URL) in any org. Replace `myDevHub` with your Dev Hub alias; the `04t…` Id and version alias below are produced by the commands themselves.

```bash
# 1. Create the package (one time)
sf package create --name "Flow Error Logger" --package-type Unlocked --path force-app --target-dev-hub myDevHub

# 2. Create a version — the CLI prints a package version Id (starts with 04t) and a version alias
sf package version create --package "Flow Error Logger" --installation-key-bypass --wait 20 --code-coverage --target-dev-hub myDevHub

# 3. Promote the version so it can be installed in any org (example alias shown)
sf package version promote --package "Flow Error Logger@1.0.0-1" --target-dev-hub myDevHub

# 4. Install the 04t Id from step 2 into your target org
sf package install --package 04tXXXXXXXXXXXXXXXX --wait 10 --target-org myorg
```

Or share the install URL (swap in the real `04t…` Id from step 2):
`https://login.salesforce.com/packaging/installPackage.apexp?p0=04tXXXXXXXXXXXXXXXX`

After installing, assign the **Flow Error Logger Admin** permission set.

## How to use it in your Flow

1. In your Flow, add a **fault connector** from any element that can fail (Get/Create/Update/Delete Records, an Apex action, a callout, etc.).
2. On the fault path, add an **Action** and search for **Log Flow Error**.
3. Map the inputs:
   - **Flow API Name** *(required)* → your flow's API name (e.g. `Account_Onboarding`).
   - **Error Message** *(required)* → `{!$Flow.FaultMessage}`.
   - **Severity** *(optional)* → `Info`, `Warning`, `Error`, or `Critical` (defaults to `Error`).
   - **Element Name / Record Id / Flow Interview GUID / Context** *(optional)* → any tracing detail you have (e.g. `{!$Flow.CurrentDateTime}` in Context).
4. Leave the action's output unmapped (or capture the returned log Ids). The action **never throws**, so it can't make your flow's failure worse.
5. Save and activate. When the fault fires, a `Flow_Error_Log__c` record appears under the **Flow Error Logs** tab.

A working example ships in this package: the **Demo Flow Error Logger** flow deliberately triggers a fault and logs it. See [Verify locally](#verify-locally).

## Field reference — `Flow_Error_Log__c`

| Field | API Name | Type | Notes |
|---|---|---|---|
| Log Number | `Name` | Auto Number | Format `FEL-{00000}` |
| Flow API Name | `Flow_API_Name__c` | Text(255) | API name of the failing flow |
| Error Message | `Error_Message__c` | Long Text(32768) | Captured fault message (truncated safely) |
| Severity | `Severity__c` | Picklist | `Info` / `Warning` / `Error` (default) / `Critical` |
| Record Id | `Record_Id__c` | Text(18) | Optional record the flow was operating on |
| Flow Interview GUID | `Flow_Interview_Guid__c` | Text(255) | Optional interview GUID for tracing |
| Element Name | `Element_Name__c` | Text(255) | Optional element/step that faulted |
| Running User | `Running_User__c` | Lookup(User) | Defaults to the current user |
| Context | `Context__c` | Long Text(32768) | Optional JSON/context payload (truncated safely) |

## Design notes

- **Bulk-safe.** `FlowErrorLogger.logErrors(List<FlowErrorLoggerRequest>)` builds every record in memory and performs a **single** DML insert, regardless of how many requests come in — no per-record DML, no governor-limit surprises.
- **Non-throwing.** The whole operation is wrapped so a logging failure is caught and swallowed. Logging must never make a Flow's failure worse. Failed inserts are reported via partial-success `Database.SaveResult` and simply return no Id.
- **Sensible defaults.** Blank/invalid `Severity` falls back to `Error`; a null Running User defaults to `UserInfo.getUserId()`; oversized text is truncated to the field length (read from the field describe) to avoid `STRING_TOO_LONG`.
- **Sharing model tradeoff.** The class is `public with sharing`, but the insert is delegated to a private `without sharing` inner class (`LogWriter`) that runs in `AccessLevel.SYSTEM_MODE`. This is a deliberate choice: **any** user — even low-privilege ones whose Flow just failed — must still be able to write an error log. Elevated access is scoped to the insert only. If your org's compliance model forbids this, remove `SYSTEM_MODE` and grant the permission set instead.

## Extension points

Want notifications? Implement the `FlowErrorNotifier` interface — no core changes required:

```apex
public interface FlowErrorNotifier {
    void notify(List<Flow_Error_Log__c> logs);
}
```

The package ships a no-op default (`FlowErrorNotifierNoOp`) so it works out of the box and never hardcodes an endpoint. To enable notifications, write your own implementation (email, Slack webhook via Named Credential, Platform Event, etc.) and set it as the active notifier:

```apex
// e.g. in a custom setup step or a small override
FlowErrorLogger.notifier = new MySlackNotifier();
```

The notifier is invoked only for successfully inserted logs, and a notifier failure is itself swallowed so it can't disrupt logging.

## Verify locally

```bash
# 1. Deploy + assign the permission set (see Install)
sf project deploy start --source-dir force-app --target-org <alias>
sf org assign permset --name Flow_Error_Logger_Admin --target-org <alias>

# 2. Run the Apex tests (targets 90%+; currently 97% on FlowErrorLogger)
sf apex run test --class-names FlowErrorLoggerTest --result-format human --code-coverage --target-org <alias>

# 3. Run the demo flow, which deliberately faults and logs
sf apex run --file scripts/apex/run_demo_flow.apex --target-org <alias>

# 4. Confirm a log record was created
sf data query --query "SELECT Name, Flow_API_Name__c, Severity__c, Error_Message__c FROM Flow_Error_Log__c ORDER BY CreatedDate DESC LIMIT 1" --target-org <alias>
```

## Tests

`FlowErrorLoggerTest` covers single + bulk (200-record) inserts, severity defaulting/validation, running-user defaulting, safe truncation of oversized text, swallowed insert failures, the null/empty input paths, and the notifier extension point (including a throwing notifier). Coverage on `FlowErrorLogger` is **97%**.

## Author

**Jonathan Leyva** — Salesforce Developer

Designed, built, tested, and documented by me as an original, reusable open-source project. If this saved you some debugging time, a ⭐ on the repo is always appreciated.

- GitHub: [@PriceFB](https://github.com/PriceFB)
- LinkedIn: [Jonathan Leyva](https://www.linkedin.com/in/leyvajonathan/)

> _Built by Jonathan Leyva · Feedback, issues, and pull requests welcome._

## License

[MIT](./LICENSE) © 2026 Jonathan Leyva

You're free to use, modify, and distribute this project. Attribution to the original author (Jonathan Leyva) is appreciated but not required.
