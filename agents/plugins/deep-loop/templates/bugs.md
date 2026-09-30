# Defect report

List only defects whose verdict is confirmed as defects. Refuted candidates go to the section for rejected candidates so nobody re-investigates them.

```markdown
# <scope> defect report
<summary: how many defects were confirmed, the most severe one, and what was covered>

## Confirmed defects
<for each, most severe first:>
### <severity>: <title>
- Location: <absolute path:line>
- Code: <quoted>
- Trigger: <input or sequence of events>
- Expected vs actual
- Evidence: <how it was confirmed: trace, test run, source>
- Suggested fix: <one or two sentences>

## Uncertain candidates
<candidates with split evidence, and what would settle each>

## Rejected candidates
<refuted candidates, one line each with why>

## Coverage
<what was examined and what was not>
```
