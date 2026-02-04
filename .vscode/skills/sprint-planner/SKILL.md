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

**CSV Format (capacity by member AND project):**
```csv
Member,Role,Project,WorkingDays,PTO,Holidays,Meetings,AvailableDays,AvailableHours,StoryPoints
@john.smith,Developer,Rockapedia,10,0,1,1,8,64,8
@john.smith,Developer,GLIR,10,0,1,1,8,64,8
@jane.doe,Developer,Rockapedia,10,2,1,1,6,48,6
```

**Key:** Members can work on multiple projects - each row is a member-project assignment.

**Formula (1 SP = 1 person day = 8 hours):**
```
AvailableDays = WorkingDays - PTO - Holidays - Meetings
AvailableHours = AvailableDays × 8
StoryPoints = AvailableDays × 1 (1 SP per available day)
```

**Capacity output per project:**
| Project | Member | Role | Available Hours | Story Points |
|---------|--------|------|-----------------|--------------|
| Rockapedia | @john.smith | Developer | 64 | 8 SP |
| Rockapedia | @jane.doe | Developer | 48 | 6 SP |
| Rockapedia | @bob.wilson | QA | 56 | 7 SP |
| **Rockapedia Total** | | | **168** | **21 SP** |

**Per-Project Capacity** = Sum of members assigned to that project

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
- [ ] Total assigned per project ≤ Project capacity
- [ ] @tagged person is assigned to that project in capacity.csv
- [ ] Each @tagged person has tasks within their available hours
- [ ] Success criteria defined for each story

**Generate outputs to** `sprint/sprint-{N}/{project}/outputs/`:

| File | Contents |
|------|----------|
| `user_stories.md` | Stories with success criteria |
| `task_breakdown.md` | Tasks with hours and assignees |
| `sprint_summary.md` | Capacity utilization report |

## 6. Human Review & Approval
**STOP** - Do not proceed to notifications until human approval.

After generating outputs, present a summary for review:

**Display review summary:**
```markdown
## 📋 Sprint {N} Planning Review - {Project}

### Metrics
| Metric | Value |
|--------|-------|
| Stories | {count} |
| Story Points | {sp} SP |
| Tasks | {tasks} |
| Total Hours | {hours}h |
| Capacity Used | {utilization}% |

### Stories for Review
| ID | Title | SP | Priority | Assignees |
|----|-------|-----|----------|-----------|
| ROCK-23-001 | Story title | 3 | High | @john, @jane |

### Capacity Allocation
| Member | Assigned | Capacity | Utilization |
|--------|----------|----------|-------------|
| @john.smith | 40h | 64h | 63% |

### ⚠️ Warnings
- Over-allocated members
- Blocked stories
- Missing assignees
```

**Prompt user for action:**
- **Approve** → Proceed to Teams notification (Phase 7)
- **Modify** → User specifies changes (adjust SP, reassign tasks, etc.)
- **Reject** → Discard and regenerate with feedback

**Review checklist (human verifies):**
- [ ] Story points reflect actual complexity
- [ ] Task assignments are balanced
- [ ] No team member is over-allocated
- [ ] Dependencies are correctly identified
- [ ] Success criteria are complete and testable
- [ ] Priority ordering is correct

**On Modify:** Apply user's changes to output files, re-validate, present updated summary.

**On Approve:** Create approval record:
```markdown
# sprint/sprint-{N}/{project}/outputs/approval.md
Approved by: {user}
Approved at: {timestamp}
Status: APPROVED
```

## 7. Notify Teams Channels via Webhooks
**Config:** `.sprint-planning/teams-webhook-alerts-config.json`

**Prerequisite:** Phase 6 approval must be complete. Check for `approval.md` file.

After approval, send notifications to Teams channels.

**Extract metrics from output files:**
```
Total Stories: Count "## {ID}:" patterns in user_stories.md
Total SP: Sum "**Story Points:** X SP" values
Total Tasks: Count "| {ID}-T" rows in task_breakdown.md
Total Hours: Sum hours column in task_breakdown.md
High Priority: Count "**Priority:** High" occurrences
Blockers: Find "**Blocked By:**" (non-None) and "⚠️" warnings
```

**Build Teams message payload:**
```json
{
  "@type": "MessageCard",
  "@context": "http://schema.org/extensions",
  "themeColor": "0076D7",
  "summary": "Sprint 23 Planning - {Project}",
  "sections": [{
    "activityTitle": "🚀 Sprint 23 - {Project} Planning Complete",
    "facts": [
      {"name": "Stories", "value": "{count}"},
      {"name": "Story Points", "value": "{sp} SP"},
      {"name": "Tasks", "value": "{tasks}"},
      {"name": "Hours", "value": "{hours}h"},
      {"name": "High Priority", "value": "{high_count}"},
      {"name": "Capacity Used", "value": "{utilization}%"}
    ],
    "markdown": true
  }]
}
```

**Send notification:**
```bash
curl -H "Content-Type: application/json" -d @payload.json {webhook_url}
```

**Per-project notification includes:**
- Sprint metrics summary
- Top 5 stories (ID, title, SP, priority)
- Team workload (member, assigned SP, hours, utilization %)
- Blockers and warnings (⚠️ items)

**Summary notification to #sprint-planning:**
- Cross-project totals
- Capacity utilization per project
- Overall team allocation

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
Project Capacity = Sum of all members assigned to project
```

**Capacity CSV columns:**
`Member, Role, Project, WorkingDays, PTO, Holidays, Meetings, AvailableDays, AvailableHours, StoryPoints`

**Epic → Project mapping:**
- Epic: Rockapedia → ROCK-XX-XXX
- Epic: GLIR → GLIR-XX-XXX
- Epic: Stratigraphy → STRAT-XX-XXX
- Epic: GOR → GOR-XX-XXX
