# Family Coordination

FamilyApp coordinates shared household routines, schedules, and responsibilities.

## Language

**User**:
An independent account that allows a person to sign in. A user may belong to multiple families and has no family role outside a membership.
_Avoid_: Member when referring to authentication

**Family**:
A private group whose members share household data and settings.

**Member**:
A participant in one family with the role of parent or child. A member may be linked to a user; participants without an account cannot sign in.

**Parent**:
A member who manages their family's settings and restrictions. All parents in a family have equal authority.
_Avoid_: Chief, owner, main admin

**Invitation**:
A one-time permission from a parent to join their family with a specified role or link an account to an existing member.

**Restriction**:
A time-bounded restriction assigned to a child in a family, with a reason and a history of changes.
_Avoid_: Punishment

**Chore**:
A scheduled household task, represented as either a regular check or a duty.

**RegularCheck**:
A recurring Yes/No question assigned to one member. Either answer finishes that check without a duty rating or debt.

**Duty**:
A scheduled household responsibility with an optional assigned member for each weekday. Completion can be performed by another member and confirmed by a parent.

**DutyOccurrence**:
One duty on one calendar date, with its original assignment and completion history.

**DutyBalance**:
A member's missed assigned duties minus confirmed duties performed for others. A positive balance is debt; ratings do not change it.

**AwayPeriod**:
An inclusive range of dates when the whole family is away and duties are excluded from the balance.

**ShoppingItem**:
An item currently needed by a family, with urgency and an optional category.

**Purchase**:
A record of buying a shopping item, optionally with a date to return it to the shared list.
