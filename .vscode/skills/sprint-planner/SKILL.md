---
name: sprint-planner
description: Automates sprint planning by reading action items, calculating team capacity, generating user stories with tasks and success criteria. Use when the user asks to "plan sprint", "generate stories", "calculate capacity", or "create task breakdown".
---

When planning a sprint, always follow these steps:

## 1. Read Action Items
**Location:** `sprint/sprint-{N}/action_items.md` (single file for all projects)

**Key mapping:**
- **Epic name = Project name** (e.g., Epic: Rockapedia → project rockapedia)
- **@tagged person** = Assigned team member for that action item

| Epic Name | Project | Story Prefix |
|-----------|---------|--------------|
| Rockapedia | rockapedia | ROCK |
| GLIR | glir | GLIR |
| Stratigraphy | stratigraphy | STRAT |
| GOR | gor | GOR |

**Action items format:**
```markdown
## Epic: Rockapedia
### Feature: User Authentication

**Story Idea:** Implement OAuth login
- Complexity: Medium
- Priority: High
- @john.smith, @jane.doe

Action Items:
- [ ] Set up OAuth provider @john.smith
- [ ] Create login UI @jane.doe
- [ ] Add session management @john.smith
```

## 2. Calculate Team Capacity
**Inputs:** `capacity.csv`, `holidays.csv`

**Formula (1 SP = 1 person day = 8 hours):**
```
AvailableDays = WorkingDays - PTO - Holidays - Meetings
AvailableHours = AvailableDays × 8
StoryPoints = AvailableDays × 1 (1 SP per available day)
```

**Capacity output per member:**
| Member | Available Days | Available Hours | Story Points |
|--------|----------------|-----------------|--------------|
| @john.smith | 8 | 64 | 8 SP |
| @jane.doe | 7 | 56 | 7 SP |

**Total Team Capacity** = Sum of all members' SP

## 3. Generate User Stories
For each Story Idea in action_items.md:

**Story ID format:** `{PREFIX}-{SPRINT}-{SEQ}` (e.g., ROCK-23-001)

**Auto-generate:**
1. **User Story** - "As a [user], I want [goal] so that [benefit]"
2. **Story Points** - Based on complexity (Simple=1, Medium=3, Complex=5)
3. **Success Criteria** - Derived from action items
4. **Assigned Members** - From @tagged persons

**Output format:**
```markdown
## ROCK-23-001: Implement OAuth Login
**Epic:** Rockapedia | **Feature:** User Authentication
**Points:** 3 SP (24 hours) | **Priority:** High
**Assigned:** @john.smith, @jane.doe

### User Story
As a user, I want to login with OAuth so that I can access my account securely.

### Success Criteria
- [ ] OAuth provider configured and tested
- [ ] Login UI matches design specs
- [ ] Session persists across browser refresh
- [ ] Logout clears session completely
- [ ] Error handling for failed auth attempts
```

## 4. Generate Tasks
Break each story into tasks based on action items and @tagged persons.

**Rules:**
- 1 Story Point = 8 hours of work
- Each task: **2-16 hours**
- Task hours MUST equal `story_points × 8`
- Assign tasks to @tagged members from action items

| Story Points | Total Hours | Task Distribution |
|--------------|-------------|-------------------|
| 1 SP | 8h | 1-2 tasks |
| 3 SP | 24h | 3-4 tasks |
| 5 SP | 40h | 4-6 tasks |

**Task output format:**
```markdown
## ROCK-23-001: Implement OAuth Login (3 SP = 24h)

| Task ID | Description | Hours | Assignee | Status |
|---------|-------------|-------|----------|--------|
| ROCK-23-001-T1 | Set up OAuth provider | 8 | @john.smith | Pending |
| ROCK-23-001-T2 | Create login UI components | 8 | @jane.doe | Pending |
| ROCK-23-001-T3 | Add session management | 6 | @john.smith | Pending |
| ROCK-23-001-T4 | Testing and code review | 2 | @jane.doe | Pending |

**Total:** 24h = 3 SP × 8 ✓
```

## 5. Validate & Output
**Validation checklist:**
- [ ] Story hours = Story Points × 8
- [ ] All tasks 2-16 hours
- [ ] Total assigned ≤ Team capacity
- [ ] Each @tagged person has tasks
- [ ] Success criteria defined for each story

**Generate outputs to** `sprint/sprint-{N}/{project}/outputs/`:

| File | Contents |
|------|----------|
| `user_stories.md` | Stories with success criteria |
| `task_breakdown.md` | Tasks with hours and assignees |
| `sprint_summary.md` | Capacity utilization report |

## Quick Reference

**Story Points:**
| Complexity | SP | Hours |
|------------|-----|-------|
| Simple | 1 | 8h |
| Medium | 3 | 24h |
| Complex | 5 | 40h |

**Capacity formula:**
```
1 Story Point = 1 Person Day = 8 Hours
Member Capacity (SP) = Available Days after PTO/Holidays/Meetings
```

**Epic → Project mapping:**
- Epic: Rockapedia → ROCK-XX-XXX
- Epic: GLIR → GLIR-XX-XXX
- Epic: Stratigraphy → STRAT-XX-XXX
- Epic: GOR → GOR-XX-XXX
