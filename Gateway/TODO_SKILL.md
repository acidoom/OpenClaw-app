# TODO Management Skill

You have access to a TODO list stored in `TODO.md`. This file syncs with the OpenClaw iOS app.

## File Location

The TODO file is located at: `files/TODO.md`

## File Format

The TODO.md file uses a structured markdown format that is both human-readable and machine-parseable:

```markdown
# TODO

## Active
- [ ] Task title
  description: Optional longer description of the task
  priority: high|medium|low
  created: 2024-02-15

- [ ] Another task
  priority: medium
  created: 2024-02-15

## Completed
- [x] Finished task
  description: What this task was about
  completed: 2024-02-10
```

## Format Rules

### Task Items
- Active tasks use `- [ ]` checkbox syntax
- Completed tasks use `- [x]` checkbox syntax
- Task title follows immediately after the checkbox on the same line

### Metadata (indented under each task)
All metadata lines must be indented with 2 spaces:

| Field | Required | Format | Description |
|-------|----------|--------|-------------|
| `description` | No | Free text | Longer description of the task |
| `priority` | No | `high`, `medium`, `low` | Task priority (defaults to `medium`) |
| `created` | Yes | `YYYY-MM-DD` | Date task was created |
| `completed` | Only for completed | `YYYY-MM-DD` | Date task was completed |

### Sections
- `## Active` - Contains all incomplete tasks
- `## Completed` - Contains all finished tasks

## Operations

### Adding a New Task

When the user asks to add a TODO, insert it under the `## Active` section:

```markdown
- [ ] New task title
  description: Optional description if provided
  priority: medium
  created: 2024-02-17
```

### Completing a Task

When the user completes a task:
1. Change `- [ ]` to `- [x]`
2. Move the task from `## Active` to `## Completed`
3. Add the `completed` date

### Updating a Task

You can modify any field (title, description, priority) while keeping the task in place.

### Deleting a Task

Simply remove the entire task block (the checkbox line and all its metadata).

### Listing Tasks

When asked to show tasks, read the file and present them in a user-friendly format:

**Active Tasks:**
- 🔴 [HIGH] Task title - description
- 🟡 [MED] Another task
- 🟢 [LOW] Low priority task

**Completed:**
- ✅ Finished task (Feb 10)

## Example Interactions

**User:** "Add a TODO to review the pull request"
**Action:** Add to `## Active`:
```markdown
- [ ] Review the pull request
  priority: medium
  created: 2024-02-17
```

**User:** "Add high priority task: Fix login bug - users can't sign in with SSO"
**Action:** Add to `## Active`:
```markdown
- [ ] Fix login bug
  description: Users can't sign in with SSO
  priority: high
  created: 2024-02-17
```

**User:** "Mark 'Review the pull request' as done"
**Action:** Move to `## Completed` and update:
```markdown
- [x] Review the pull request
  priority: medium
  created: 2024-02-17
  completed: 2024-02-17
```

**User:** "What's on my TODO list?"
**Action:** Read `TODO.md` and present tasks grouped by priority.

## Sync Behavior

- The OpenClaw iOS app syncs with this file automatically
- Changes made here appear in the app within seconds
- Changes made in the app update this file
- Always read the latest version before making changes to avoid conflicts

## Best Practices

1. **Always use ISO dates** (YYYY-MM-DD) for consistency
2. **Keep titles concise** - put details in description
3. **Set appropriate priority** - helps with sorting in the app
4. **Add descriptions** for complex tasks
5. **Clean up old completed tasks** periodically (archive or delete)
