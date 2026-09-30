export const meta = {
  name: 'deep-loop-round',
  description: 'deep-loop の 1 ラウンド: 未解決の問いから課題を立て、作業役を並列に走らせ、影響の大きい知見を反証し、state を書き直す',
  phases: [
    { title: 'Plan', detail: '未解決の問いから課題を立てる' },
    { title: 'Work', detail: '課題ごとの作業役' },
    { title: 'Verify', detail: '影響の大きい知見を崩しにいく' },
    { title: 'Integrate', detail: 'state を書き直し、問いを開閉する' },
  ],
}

// args は deep-loop:run の skill が組み立てる。script はファイルに触れられないので、読み書きはすべてエージェントが行う。
// 経緯はこの script の変数と作業ディレクトリのファイルにだけ持ち、メインのセッションには要約だけを返す。
const A = args
const M = A.models
const E = A.efforts
const R = 'r' + String(A.round).padStart(2, '0')
const roundDir = A.roundsDir + '/' + R

const EVIDENCE_RULES = [
  '- Never fabricate. Do not speculate. Every factual claim needs a source and a verbatim quote from it. A claim without a source is not a finding: record it as a gap.',
  '- A source is a web page URL or an absolute file path (code in the repositories, or a file you saved in your scratch_dir).',
  '- Copy quotes character for character from the source, in its language. Never translate or paraphrase a quote. Keep each quote short (one or two sentences, or a few lines of code); join omitted parts with "...".',
  '- Every time you write claims_path, a hook checks each quote against its source by string matching and tells you which ones failed. Fix or drop failed claims and rewrite the file. Claims whose quote is not found never become findings.',
  '- When sources disagree, record the disagreement with both sources. Do not pick a side silently.',
  '- Finding nothing new, or no defect, is a valid outcome. Say so plainly instead of padding.',
].join('\n')

const WORKER_FILES = [
  '## Files',
  '- The repositories are read-only. Never modify them, never commit, push, or post anything to external services.',
  '- Write only notes_path, claims_path and files under scratch_dir. Put every intermediate file (downloads, extracted strings, copies, experiment scripts) in scratch_dir.',
  '- Write notes_path and claims_path with the Write tool, not with shell redirection, so the citation check runs and reports back to you.',
  '- claims_path is a JSON array of the factual claims your notes rely on: {"claim": "<one sentence>", "source": "<URL or absolute path>", "quote": "<verbatim excerpt>"}. Write [] when you make no factual claims.',
  '- Do all the work yourself in this session. Do not start subagents.',
  '',
  '## Return value',
  '- summary: two or three sentences on what you established.',
  '- answered: the question ids from the task that you answered, each with a one-line answer. Leave out questions you could not settle.',
  '- raised_questions: new questions that matter to the brief and that you could not settle (may be empty).',
  '- high_impact: the findings the final answer would depend on (key facts, design blockers, suspected defects), at most eight, each with a short id, a one-sentence statement and where the evidence is. A separate reviewer will try to refute each one.',
].join('\n')

const WORKER_ROLES = {
  investigate: [
    '# Investigator',
    'You establish the facts for one narrow task. Other workers cover adjacent tasks in parallel, so stay within your scope. Nobody will research further on your behalf: your notes must be self-contained and well sourced.',
    '',
    '## How to research',
    '1. Reflect on which gaps remain for your objective and key questions.',
    '2. Search: web search with short queries (under five words), or grep and glob in the repositories.',
    '3. Read the full page or file behind promising results. Snippets are easy to take out of context.',
    '4. Repeat until the key questions are answered with sourced findings, you stop finding new information, or you reach about 20 tool calls.',
    'Never repeat the exact same query. Run searches and reads in parallel where you can. For recent topics, trust current sources over your training data.',
    '',
    '## Evaluating sources',
    'Ask whether a statement is confirmed fact or speculation, whether the source is primary (official documentation, specifications, source code, papers) or an aggregator, and whether it shows warning signs (nameless sources, vague qualifiers). When information is sparse or unreliable, say so.',
    '',
    '## Notes format',
    '# <slug>, then for each key question: "## <question>", "### Takeaway" (one or two sentences), "### Cited findings" (fact, then source), "### Inferences" (marked as inference), "### Gaps" (what could not be answered and why).',
  ].join('\n'),
  propose: [
    '# Proposer',
    'You draft one design (or one refactoring plan) that meets the requirements in the brief. Other proposers may draft alternatives in parallel; commit to the approach in your task instead of hedging.',
    '',
    '## How to work',
    '- Read the code and documents your design touches before deciding. Ground every statement about existing code, services or libraries in a claim with a verbatim quote.',
    '- The brief is the ceiling: never add requirements of your own. Prefer the smallest design that meets every requirement, and follow the conventions of the existing code.',
    '- About 25 tool calls at most.',
    '',
    '## Notes format',
    '# <slug>; ## Summary (three to five sentences); ## How it meets each requirement; ## Key decisions (decision, why, what it depends on); ## Steps (for a refactoring plan: ordered, each independently shippable, with its risk); ## What it gives up; ## Open questions.',
  ].join('\n'),
  critique: [
    '# Critic',
    'You review the files in read_first adversarially. Find what would make the design, plan or findings wrong; do not rewrite them.',
    '',
    '## What to look for',
    '- A requirement that is not met, or met only under an unstated assumption. Judge against the brief only; do not add requirements.',
    '- Behaviour on failure: partial failure, retries, concurrency, ordering, data loss, migration and rollback.',
    '- Statements about existing code or external services that the code or documentation contradicts. Check them yourself.',
    '- Parts that no requirement needs. Conflicts with the settled findings in the state.',
    'Rate each issue critical (does not work or misses a requirement), major (works with a significant risk or cost) or minor, with evidence and what would resolve it. When you find no critical issue, say so plainly: that is a valid outcome.',
    '',
    '## Notes format',
    '# <slug>; ## Verdict (one or two sentences); ## Issues, each "### <critical|major|minor>: <title>" with Evidence and Resolution.',
  ].join('\n'),
  hunt: [
    '# Defect hunter',
    'You look for latent defects in the scope of your task. Report only defects that change behaviour: wrong results, crashes, data loss or corruption, security holes, resource leaks, race conditions, contract mismatches between callers and callees. Style and naming are out of scope.',
    '',
    '## How to hunt',
    '- Read the code in scope end to end, then follow its callers and callees across module boundaries. Use distinct lenses: error and edge paths, concurrency and ordering, boundaries and units, resource lifetime, trust boundaries, assumptions that other code relies on.',
    '- For each candidate, write the exact location (absolute path and line), quote the code, and give a concrete trigger: the input or sequence of events, what happens, and what should happen. If you can demonstrate it with an existing test or a script in scratch_dir without touching the repository, do so and record the command and output.',
    '- Every candidate goes into high_impact; a reviewer will try to refute each one. Do not inflate severity.',
    '- About 30 tool calls at most.',
    '',
    '## Notes format',
    '# <slug>; ## Scope covered (what you read, so later rounds know what is done); ## Candidates, each "### <severity>: <title>" with Location, Code, Trigger, Expected vs actual, Confidence; ## Areas not covered.',
  ].join('\n'),
}

const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['continue', 'done'] },
    reason: { type: 'string' },
    tasks: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          slug: { type: 'string', pattern: '^[a-z0-9][a-z0-9-]{0,47}$' },
          kind: { type: 'string', enum: ['investigate', 'propose', 'critique', 'hunt'] },
          objective: { type: 'string' },
          key_questions: { type: 'array', items: { type: 'string' } },
          resolves: { type: 'array', items: { type: 'string' } },
          sources: { type: 'array', items: { type: 'string' } },
          read_first: { type: 'array', items: { type: 'string' } },
          serves: { type: 'string' },
        },
        required: ['slug', 'kind', 'objective', 'key_questions', 'resolves', 'sources', 'read_first', 'serves'],
      },
    },
  },
  required: ['status', 'reason', 'tasks'],
}

const WORK_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    answered: {
      type: 'array',
      items: {
        type: 'object',
        properties: { question_id: { type: 'string' }, answer: { type: 'string' } },
        required: ['question_id', 'answer'],
      },
    },
    raised_questions: { type: 'array', items: { type: 'string' } },
    high_impact: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, statement: { type: 'string' }, evidence: { type: 'string' } },
        required: ['id', 'statement', 'evidence'],
      },
    },
  },
  required: ['summary', 'answered', 'raised_questions', 'high_impact'],
}

const VERDICTS_SCHEMA = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
          reasoning: { type: 'string' },
          evidence: { type: 'string' },
        },
        required: ['id', 'verdict', 'reasoning', 'evidence'],
      },
    },
  },
  required: ['verdicts'],
}

const INTEGRATE_SCHEMA = {
  type: 'object',
  properties: {
    progress: { type: 'integer', minimum: 0 },
    resolved_questions: { type: 'array', items: { type: 'string' } },
    open_questions: { type: 'integer', minimum: 0 },
    summary: { type: 'string' },
    suggest_done: { type: 'boolean' },
  },
  required: ['progress', 'resolved_questions', 'open_questions', 'summary', 'suggest_done'],
}

function planPrompt() {
  return [
    '# Planner',
    'You plan round ' + A.round + ' of at most ' + A.maxRounds + ' of a long-running effort. The effort may be research, a pre-implementation design, a refactoring investigation, a hunt for latent defects, or a mix, as the brief says. You do not do the work yourself.',
    '',
    '## Input',
    '- The brief (below) was written by a human. It never changes between rounds and it is the ceiling: never add requirements.',
    '- The state document at ' + A.statePath + ' holds the open questions (with ids such as Q3), resolved questions, findings, candidates and decisions, contradictions and dead ends. Read it first. It does not exist on round 1.',
    '- Earlier rounds: ' + (A.previous.length === 0 ? 'none' : A.previous.join(' | ')),
    '- Earlier rounds\' notes live under ' + A.roundsDir + '/<round>/<slug>.md. Use absolute paths in read_first.',
    '- Repositories (read-only): ' + (A.repos.length === 0 ? 'none' : A.repos.join(', ')),
    '',
    '## The question loop',
    'The effort advances by opening questions and closing them. Plan tasks that close the open questions in the state; each task lists in resolves the ids it aims to close (empty on round 1, when the state has no ids yet). Contradictions, unverified claims that matter, refuted or uncertain high-impact findings and unresolved critique issues are open questions too.',
    '',
    '## Task kinds',
    '- investigate: establish facts from web sources or the repositories.',
    '- propose: draft one design or refactoring plan. When the design space is open, plan two or more proposals with genuinely different approaches.',
    '- critique: review proposals or findings adversarially against the brief; list the files in read_first.',
    '- hunt: look for latent defects in one part of the code; split a large codebase by module or by lens.',
    '',
    '## Rules',
    '- Scout only enough to split the work: list files, check sizes, skim structure, about ten quick reads at most. Do not analyse the code or sources for answers yourself; that is what the workers are for, and they are cheaper.',
    '- Decompose into tasks that do not overlap and together cover what is still missing. Give independent points of view their own tasks.',
    '- The number of tasks follows from the decomposition, not from a target: one for a single fact, about three for a focused topic, more for a large codebase or an enumerable set. There is no upper limit, but every task must be necessary.',
    '- Do not redo what the state records as settled or covered, and do not retry a dead end without a genuinely different angle.',
    '- Give each task a precise brief: objective (what must be known or produced when it is done), key_questions, sources (kinds of sources or code areas to prioritise), read_first, and serves (which part of the brief it answers). Drop a task for which you cannot write serves.',
    '- This is round ' + A.round + ' of ' + A.maxRounds + '. ' + (A.round === A.maxRounds ? 'It is the last round: plan the tasks that close the questions the deliverable most depends on, and if the brief asks for a design or plan whose leading candidate has not been critiqued, include that critique.' : 'Leave room for later rounds; do not try to finish everything now.'),
    '- Return status "done" with a reason when the brief is answered to the degree the sources allow, or when the remaining questions cannot be answered from available sources. A design or plan is done only after its leading candidate has survived a critique with no unresolved critical issue. Ending early is a normal outcome: do not invent tasks.',
    '- slug: lowercase ASCII letters, digits and hyphens, unique within the round.',
    '',
    '## Brief',
    A.brief,
  ].join('\n')
}

function workerPrompt(task) {
  const input = {
    task: {
      kind: task.kind,
      objective: task.objective,
      key_questions: task.key_questions,
      resolves: task.resolves,
      sources: task.sources,
      serves: task.serves,
    },
    state_path: A.statePath,
    read_first: task.read_first,
    repositories: A.repos,
    notes_path: roundDir + '/' + task.slug + '.md',
    claims_path: roundDir + '/' + task.slug + '.claims.json',
    scratch_dir: roundDir + '/' + task.slug + '.work',
  }
  return [
    WORKER_ROLES[task.kind],
    '',
    '## Input',
    'Read the state document first so you do not repeat settled work, then the files in read_first. Write your notes in English.',
    JSON.stringify(input, null, 2),
    '',
    '## Evidence',
    EVIDENCE_RULES,
    '',
    WORKER_FILES,
    '',
    '## Brief (context only; your task is the scope)',
    A.brief,
  ].join('\n')
}

// 反証役は課題ごとに 1 本にする。知見ごとに起こすと同じコードを何本もが読み直し、費用の 7 割を反証が占めた（実測）。
// 書いた本人とは別のエージェントが崩しにいくという独立性は、課題ごとでも保たれる
function verifyPrompt(task, work) {
  return [
    '# Skeptic',
    'Try to refute each finding below, one by one. Read the evidence yourself: the notes at ' + roundDir + '/' + task.slug + '.md, the claims and their check results next to it (' + task.slug + '.claims.json, ' + task.slug + '.checks.json), and the cited sources or code.',
    '',
    'Findings from the ' + task.kind + ' task "' + task.slug + '":',
    ...work.high_impact.map((finding) => '- ' + finding.id + ': ' + finding.statement + ' (evidence: ' + finding.evidence + ')'),
    '',
    '## Rules',
    '- For a fact: check that the cited source says it, and look for a primary source that contradicts it.',
    '- For a suspected defect: read the code path yourself and trace the trigger. Either show the concrete input or sequence that causes it, or show why the path cannot be reached (a guard, a caller that never passes that value, a type that forbids it). You may run existing tests or read-only commands; do not modify the repositories.',
    '- For a design blocker or plan risk: check whether the brief actually requires what the finding says is missed.',
    '- Judge each finding on its own evidence; do not let one verdict carry over to another.',
    '- If you cannot establish a finding, answer refuted. Answer uncertain only when the evidence is genuinely split. Do not start subagents.',
    '- Return one verdict per finding id: verdict, reasoning (two to four sentences) and evidence (the source or code location that decided it).',
  ].join('\n')
}

function integratePrompt(done, failed) {
  const tasks = done.map((entry) => ({
    kind: entry.task.kind,
    slug: entry.task.slug,
    objective: entry.task.objective,
    resolves: entry.task.resolves,
    notes_path: roundDir + '/' + entry.task.slug + '.md',
    checks_path: roundDir + '/' + entry.task.slug + '.checks.json',
    summary: entry.work.summary,
    answered: entry.work.answered,
    raised_questions: entry.work.raised_questions,
    high_impact_verdicts: entry.verdicts,
  }))
  return [
    '# Integrator',
    'You merge round ' + A.round + ' into the state document. It is the only memory that carries over to the next round, so what you drop is forgotten.',
    '',
    '## Input',
    '- The brief (below). The current state at ' + A.statePath + ' (absent on round 1).',
    '- This round\'s tasks with their notes, claim checks and the verdicts on their high-impact findings:',
    JSON.stringify(tasks, null, 2),
    '- Tasks whose worker failed: ' + (failed.length === 0 ? 'none' : failed.map((task) => task.slug + ' (' + task.objective + ')').join('; ')),
    '- checks_path holds, for every quoted claim, verified (the quote is in the source), not_found (the source was read and the quote is not in it) or unverifiable (the source could not be read as text).',
    '',
    '## Write the new state to ' + A.nextStatePath,
    'Rewrite it from scratch; do not append. At most ' + A.stateMaxLines + ' lines. Write it in the language of the brief. Sections, in this order (omit an empty one):',
    '1. Open questions: "- Q<n> (r<round raised>): <question> — <why it matters to the brief>". Keep ids stable across rounds and never reuse one. On round 1, derive the questions from the brief and this round\'s results.',
    '2. Resolved questions: "- Q<n>: <answer> (<notes path or source>)". Close a question only with evidence.',
    '3. Findings: settled facts, one per line, each with its source and notes path. Only claims whose check is verified become findings; an unverifiable claim may appear only marked "(unverified)".',
    '4. Candidates and decisions: designs, refactoring plans or defect candidates, each with its notes path and status (proposed, survived critique, rejected with the reason; for defects: confirmed, refuted, uncertain).',
    '5. Contradictions and unverified claims: disagreeing sources, not_found claims (never as findings), uncertain verdicts.',
    '6. Dead ends and rejected options: what yielded nothing and what was rejected, with why, so later rounds do not retry it.',
    '',
    '## Rules',
    '- A high-impact finding that was refuted is not a finding; record it under dead ends or as a refuted candidate. An uncertain one becomes an open question.',
    '- Failed tasks leave their questions open. Add raised questions only if they matter to the brief; the brief is the ceiling.',
    '- Carry over everything still valid. Only the notes, checks, verdicts and current state are evidence; add no knowledge of your own. When the document grows long, merge related lines instead of dropping them.',
    '- progress counts what is new this round: findings, candidates, decisions, questions resolved, defects confirmed or refuted. suggest_done is true when no open question that matters to the deliverable remains.',
    '- summary is one line of at most 200 characters, and resolved_questions lists question ids only (such as "Q3"). The details belong in the state document; the summary is what the orchestrator keeps from this round.',
    '- Do not start subagents.',
    '',
    '## Brief',
    A.brief,
  ].join('\n')
}

phase('Plan')
const plan = await agent(planPrompt(), {
  label: 'planner',
  phase: 'Plan',
  schema: PLAN_SCHEMA,
  model: M.planner,
  effort: E.planner,
})
if (plan === null) return { status: 'failed', round: A.round, reason: 'planner failed' }
if (plan.status === 'done') return { status: 'done', round: A.round, reason: plan.reason }

// planner が同じ slug を 2 度返すと、並列の作業役が同じノートを奪い合う
const seen = new Set()
const tasks = plan.tasks.filter((task) => !seen.has(task.slug) && seen.add(task.slug))
log(R + ': ' + tasks.length + ' tasks (' + tasks.map((task) => task.kind + ':' + task.slug).join(', ') + ')')

const results = await pipeline(
  tasks,
  (task) =>
    agent(workerPrompt(task), {
      label: task.kind + ':' + task.slug,
      phase: 'Work',
      schema: WORK_SCHEMA,
      model: M.worker,
      effort: E.worker,
    }),
  async (work, task) => {
    if (work === null) return null
    if (work.high_impact.length === 0) return { task, work, verdicts: [] }
    const judged = await agent(verifyPrompt(task, work), {
      label: 'verify:' + task.slug,
      phase: 'Verify',
      schema: VERDICTS_SCHEMA,
      model: M.verifier,
      effort: E.verifier,
    })
    const byId = new Map((judged?.verdicts ?? []).map((verdict) => [verdict.id, verdict]))
    return {
      task,
      work,
      // 反証役が落ちたか判定を返さなかった知見は、確かめられていないものとして不明に倒す
      verdicts: work.high_impact.map((finding) => ({
        id: finding.id,
        statement: finding.statement,
        ...(byId.get(finding.id) ?? { verdict: 'uncertain', reasoning: 'the skeptic returned no verdict', evidence: '' }),
      })),
    }
  },
)

const done = results.filter(Boolean)
const failed = tasks.filter((_task, index) => !results[index])
if (failed.length > 0) log(R + ': failed tasks: ' + failed.map((task) => task.slug).join(', '))
if (done.length === 0) return { status: 'failed', round: A.round, reason: 'every task failed', plan }

phase('Integrate')
const integrated = await agent(integratePrompt(done, failed), {
  label: 'integrator',
  phase: 'Integrate',
  schema: INTEGRATE_SCHEMA,
  model: M.integrator,
  effort: E.integrator,
})
if (integrated === null) return { status: 'failed', round: A.round, reason: 'integrator failed', plan }

const verdictCount = (kind) =>
  done.reduce((sum, entry) => sum + entry.verdicts.filter((v) => v.verdict === kind).length, 0)
return {
  status: 'ok',
  round: A.round,
  tasks: tasks.map((task) => ({ slug: task.slug, kind: task.kind, resolves: task.resolves })),
  failed: failed.map((task) => task.slug),
  verdicts: { confirmed: verdictCount('confirmed'), refuted: verdictCount('refuted'), uncertain: verdictCount('uncertain') },
  highImpact: done.flatMap((entry) => entry.verdicts.map((v) => ({ task: entry.task.slug, ...v }))),
  outputTokens: budget.spent(),
  ...integrated,
}
