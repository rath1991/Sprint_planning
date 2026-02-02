---
name: sprint-planner
description: Automates sprint planning by reading action items, calculating team capacity, generating user stories with unique IDs, breaking stories into tasks, and producing sprint outputs. Use when the user asks to "plan sprint", "generate stories", "calculate capacity", or "create task breakdown".
---

When planning a sprint, always follow these steps:

## 1. Read Inputs
- **Action Items**: `sprint/sprint-{N}/{project}/action_items.md` for each project (rockapedia, glir, stratigraphy, gor)
- **Capacity**: `sprint/sprint-{N}/capacity.csv`
- **Holidays**: `sprint/sprint-{N}/holidays.csv`
- **Config**: `sprint/config.json`

## 2. Calculate Team Capacity
```
AvailableDays = WorkingDays - PTO - Holidays - Meetings
AvailableHours = AvailableDays × 8
StoryPoints = AvailableDays × 1 (per config)
```
Sum all members for total team capacity.

## 3. Generate Unique Story IDs
Format: `{PREFIX}-{SPRINT}-{SEQ}` (e.g., ROCK-23-001, GLIR-23-002)

| Project | Prefix |
|---------|--------|
| rockapedia | ROCK |
| glir | GLIR |
| stratigraphy | STRAT |
| gor | GOR |

## 4. Estimate Story Points
| Complexity | Points |
|------------|--------|
| Simple | 1 |
| Medium | 3 |
| Complex | 5 |

Add +1 point if story has dependencies.

## 5. Break Stories into Tasks
**Rules:**
- Each task: **2-16 hours** (no exceptions)
- Task hours must equal `story_points × 8`
- Include: Dev, Code Review, QA, Documentation tasks

| Points | Hours | Typical Split |
|--------|-------|---------------|
| 1 | 8 | 2 tasks @ 4h |
| 3 | 24 | 3 tasks @ 8h |
| 5 | 40 | 5 tasks @ 8h |

## 6. Assign Tasks
1. Sort stories by priority (High → Medium → Low)
2. Match task type to member role (QA tasks → QA members)
3. Assign to member with most remaining capacity
4. Flag if over capacity

## 7. Validate Before Output
- [ ] Task hours = Story points × 8 (per story)
- [ ] All tasks 2-16 hours
- [ ] Total assigned ≤ Team capacity
- [ ] All tasks have assignees
- [ ] Dependencies scheduled correctly

## 8. Generate Outputs
Save to `sprint/sprint-{N}/{project}/outputs/`:
- `user_stories.md` - Full story details with acceptance criteria
- `task_breakdown.md` - Tasks table with hours and assignees
- `sprint_plan.xlsx` - Summary with capacity utilization

## Quick Reference

**Story format:**
```markdown
## ROCK-23-001: Story Title
**Points:** 3 | **Priority:** High | **Epic:** User Management
As a [user], I want [goal] so that [benefit].
```

**Task table format:**
```markdown
| Task ID | Description | Hours | Assignee | Type |
|---------|-------------|-------|----------|------|
| ROCK-23-001-T1 | Implement feature | 8 | John | Dev |
```

**Common errors:**
- E003: Task hours mismatch → Adjust to match points × 8
- E004: Over capacity → Defer low-priority stories
