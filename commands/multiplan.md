---
description: Generate multiple viable interpretations for ambiguous requests
argument-hint: [user request]
---

# AI Agent Instructions: Multi-Plan Ambiguity Resolution

## Core Behavior
When you receive a user request that contains significant ambiguity (insufficient specificity to execute with confidence), automatically generate multiple viable interpretations instead of asking for clarification or making assumptions.

## Ambiguity Detection
Trigger multi-plan mode when user input lacks critical parameters such as:
- Specific values (colors, sizes, quantities)
- Target objects/locations when multiple options exist
- Method/approach when multiple valid approaches exist
- Scope/boundaries of the requested action

## Multi-Plan Generation Process
1. **Spawn Planning**: Generate 3-5 distinct, reasonable interpretations of the user's request
2. **Ensure Diversity**: Each plan should represent a meaningfully different approach, not just parameter variations
3. **Rank by Likelihood**: Order options based on context, user history, and common patterns
4. **Format for Selection**: Present as numbered list with clear selection prompt

## Response Format
```
I need to clarify your request since there are several ways to interpret "$ARGUMENTS". Here are the most likely options:

1. [Interpretation 1 - brief description]
2. [Interpretation 2 - brief description] 
3. [Interpretation 3 - brief description]
4. [Interpretation 4 - brief description]
5. [Interpretation 5 - brief description]

Which option should we go with? Just reply with the number (e.g., "2") or tell me if none of these match what you had in mind.
```

## Selection Handling
- Wait for user to respond with a number/letter or description
- When user selects an option, immediately proceed with that plan
- If user provides additional details instead of selecting, incorporate those and proceed
- If user says "none" or rejects all options, ask for more specific clarification

## Don't Multi-Plan When
- Request is already sufficiently specific
- Only one reasonable interpretation exists
- User has provided explicit constraints that eliminate ambiguity
- Previous context makes the intent clear

## Examples of Multi-Plan Triggers
- "Change the color" → Which color? Which element?
- "Make it bigger" → How much bigger? Which dimension?  
- "Fix the bug" → Which bug? Which approach?
- "Add a button" → Where? What style? What action?

## Key Principles
- **Speed over perfection**: Better to give good options quickly than perfect options slowly
- **User agency**: Always let the user choose rather than guessing
- **Learn from selections**: Note user preferences for future similar requests
- **Clear communication**: Make it obvious how to select an option

Execute this behavior consistently across all interactions where ambiguity is detected.