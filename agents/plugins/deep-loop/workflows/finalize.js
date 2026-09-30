export const meta = {
  name: 'deep-loop-finalize',
  description: 'deep-loop の最終の成果物を、state と各ラウンドのノートと照合結果から書く',
  phases: [{ title: 'Write', detail: '最終の成果物' }],
}

const A = args

const RESULT_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    open_questions: { type: 'integer', minimum: 0 },
  },
  required: ['summary', 'open_questions'],
}

const prompt = [
  '# Final writer',
  'You write the deliverable of a long-running effort from its files. You do not research further.',
  '',
  '## Input',
  '- The brief (below). Its "Deliverable" says which template to follow; the templates are in ' + A.templatesDir + ' (research.md, design.md, refactor.md, bugs.md). Read the one that matches; when the brief mixes kinds, combine the relevant sections.',
  '- The final state document at ' + A.statePath + '. Use it as the index of what is known, decided and still open.',
  '- Every round under ' + A.roundsDir + '/<round>/: notes (<slug>.md), claim checks (<slug>.checks.json) and the round result (result.json, with the verdicts on high-impact findings). Read the notes behind what you use; do not rely on the state\'s one-line summaries alone.',
  '',
  '## Evidence',
  '- Use only claims that the checks show as verified. An unverifiable claim may appear only marked as unverified. Never present a not_found claim, or a refuted high-impact finding, as fact.',
  '- Cite sources inline after the claims a reader would want to check: ([Source](URL)) for web pages, the absolute path with line numbers for code.',
  '- State plainly what is uncertain, contested or unanswered, and why. Every question still open in the state appears in the section for open questions, phrased so a human can answer it.',
  '',
  '## Rules',
  '- Write in the language of the brief, to ' + A.reportPath + '. Match the length to the brief: decision-ready precision for engineering work, depth for broad research.',
  '- Do not start subagents.',
  '- Return a two-sentence summary of the deliverable and the number of open questions it lists.',
  '',
  '## Brief',
  A.brief,
].join('\n')

phase('Write')
const result = await agent(prompt, {
  label: 'writer',
  phase: 'Write',
  schema: RESULT_SCHEMA,
  model: A.models.writer,
  effort: A.efforts.writer,
})
if (result === null) return { status: 'failed', reason: 'writer failed' }
return { status: 'ok', reportPath: A.reportPath, outputTokens: budget.spent(), ...result }
