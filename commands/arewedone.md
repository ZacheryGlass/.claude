---
description: Run structural completeness review
---

# 1. Structural Completeness Review

Use the structural-completeness-reviewer agent to check if recent changes are fully integrated and no technical debt was introduced.

Launch the structural-completeness-reviewer agent to verify:
- Changes are fully integrated
- Old code is properly removed  
- No technical debt introduced
- Structural integrity maintained

# 2. Address Review Comments

After the agent returns its review results, you should immediately make the recommended updates. 

# 3. Commit the changes

Use the committer agent to create a conventional commit for all the completed changes. 