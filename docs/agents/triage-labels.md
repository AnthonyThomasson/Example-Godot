# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

An issue with no state label counts as `needs-triage`.

## Category roles

| Role in mattpocock/skills | In our tracker |
| ------------------------- | -------------- |
| `bug`                     | `bug`          |
| `enhancement`             | no label: any issue without `bug` or `spike` (`ai`, `harness`, `assets`, … are kinds of enhancement the `ticket` skill routes on) |

`spike` is a third kind, an investigation that plans tickets; the `ticket` skill routes it. Topic labels (`physics`,
`navigation`, …) are not categories. Rejected enhancements are recorded in `.out-of-scope/<concept>.md`.

Edit the "Label in our tracker" column to match whatever vocabulary you actually use.
