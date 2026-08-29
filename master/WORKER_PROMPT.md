# Standard worker prompt

Each owner starts their agent with this prompt, substituting only their name:

```text
I am <Vidya | Suprith | Tushar>. Work only on my current work package in
master/ROLES.md and follow my detailed pickup plan in handovers/<NAME>_WORK_PLAN.md.

First read, in full: master/RULES.md, master/ARCHITECTURE.md,
master/ROLES.md, and my pickup plan. Inspect the current main before editing.
Treat all other owners' files as read-only except for an agreed public contract.
Implement the next unchecked package in my plan, add the required tests, run
the stated verification, and update the package's evidence checklist. Do not
push, merge another branch, add real user data, or claim an unmeasured/runtime
scaffold is complete. Stop only when the package acceptance contract is met or
when a concrete cross-owner contract decision is required.
```

## Shared handoff rule

An owner hands off only a small public contract, test fixture, and implementation
in their owned paths. The next owner should be able to work against that contract
without editing the prior owner's implementation. Every PR must name the role
package, list tests run, and state remaining device-only verification.
