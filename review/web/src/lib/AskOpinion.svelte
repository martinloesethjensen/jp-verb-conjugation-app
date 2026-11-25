<script lang="ts">
	// "Ask for a second opinion" under an item's open suggestions: a button that opens the panel, where the asker
	// picks a colleague, adds a question and asks. The people load when it opens, not before. The person asked
	// sees the suggestions and picks one, or says why neither works; the asker still decides.
	import { tick, untrack } from 'svelte';
	import { askOpinion, getCandidates, problem, type Candidate, type Target } from './api.ts';
	import ErrorLine from './ErrorLine.svelte';
	import { roleLabel } from './labels.ts';
	import { askLabel, askLead, firstCandidate, seenNote, stepIndex } from './opinions.ts';

	let {
		target,
		onasked,
		count = 2,
		open: startOpen = false,
		candidates: given = null,
		error = null
	}: {
		target: Target;
		onasked: () => void;
		/** How many open suggestions the person asked will see. */
		count?: number;
		/** Whether the panel starts open (for tests). */
		open?: boolean;
		/** The people who can be asked; loaded when the panel opens if not given (the given list is for tests). */
		candidates?: Candidate[] | null;
		/** A message to start with (for tests). */
		error?: string | null;
	} = $props();

	const uid = $props.id();
	// The given values only seed the state.
	let opened = $state(untrack(() => startOpen));
	let candidates = $state<Candidate[] | null>(untrack(() => given));
	let chosen = $state<number | null>(untrack(() => (given ? firstCandidate(given) : null)));
	let question = $state('');
	let busy = $state(false);
	let failure = $state<string | null>(untrack(() => error));
	let heading = $state<HTMLElement>();

	async function open() {
		opened = true;
		await tick();
		heading?.focus();
		if (candidates) return;
		try {
			candidates = await getCandidates(target);
			chosen = firstCandidate(candidates);
		} catch (e) {
			candidates = [];
			failure = problem(e);
		}
	}

	let group = $state<HTMLElement>();

	/** Arrow keys move the choice (and focus) round the group; Space or Enter on a focused radio picks it. */
	function key(event: KeyboardEvent) {
		const delta = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0;
		if (!delta || !candidates?.length) return;
		event.preventDefault();
		const at = candidates.findIndex((c) => c.user === chosen);
		const next = stepIndex(at, delta, candidates.length);
		chosen = candidates[next].user;
		group?.querySelectorAll<HTMLElement>('[role="radio"]')[next]?.focus();
	}

	async function ask(event: SubmitEvent) {
		event.preventDefault();
		if (chosen === null || busy) return;
		busy = true;
		failure = null;
		try {
			await askOpinion(target, chosen, question.trim());
			onasked();
		} catch (e) {
			failure = problem(e);
		} finally {
			busy = false;
		}
	}
</script>

{#if !opened}
	<button type="button" class="open" aria-expanded="false" onclick={open}>Ask for a second opinion</button>
{:else if candidates === null || candidates.length || failure}
	<form class="ask" onsubmit={ask} aria-labelledby="{uid}-heading">
		<h3 id="{uid}-heading" tabindex="-1" bind:this={heading}>Ask for a second opinion</h3>
		<p class="lead">{askLead(count)}</p>
		{#if candidates === null}
			<p class="lead">Loading…</p>
		{:else if candidates.length}
			<div class="people" role="radiogroup" aria-label="Who to ask" bind:this={group}>
				{#each candidates as c, i (c.user)}
					<button
						type="button"
						role="radio"
						class="person"
						aria-checked={chosen === c.user}
						tabindex={chosen === c.user || (chosen === null && i === 0) ? 0 : -1}
						onclick={() => (chosen = c.user)}
						onkeydown={key}
					>
						<span class="initial" aria-hidden="true">{(Array.from(c.name.trim())[0] ?? '?').toUpperCase()}</span>
						<span class="who"
							><span class="name">{c.name}</span><span class="note">{roleLabel(c.role)} · {seenNote(c)}</span></span
						>
					</button>
				{/each}
			</div>
			<label for="{uid}-question">Your question (optional)</label>
			<input id="{uid}-question" type="text" bind:value={question} autocomplete="off" />
			<div class="row">
				<button type="submit" class="primary" disabled={busy || chosen === null}>{askLabel(candidates, chosen)}</button>
				<button type="button" class="link" onclick={() => (opened = false)}>Cancel</button>
			</div>
		{/if}
		<ErrorLine message={failure} />
	</form>
{/if}

<style>
	.open {
		min-height: 44px;
		margin-top: 1rem;
	}

	.ask {
		margin-top: 1rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	h3 {
		margin: 0 0 0.25rem;
		font-size: 1rem;
	}

	.lead {
		margin: 0 0 0.75rem;
		font-size: 0.9rem;
		color: var(--muted);
	}

	.people {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-bottom: 0.9rem;
	}

	.person {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		min-height: 52px;
		padding: 0.4rem 0.75rem;
		text-align: left;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.person[aria-checked='true'] {
		border: 2px solid var(--ink);
	}

	.initial {
		display: grid;
		place-items: center;
		flex: none;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		background: var(--well);
		font-weight: 700;
	}

	.who {
		display: flex;
		flex-direction: column;
	}

	.name {
		font-weight: 600;
	}

	.note {
		font-size: 0.85rem;
		color: var(--muted);
	}

	label {
		display: block;
		margin-bottom: 0.25rem;
		font-size: 0.9rem;
	}

	input {
		box-sizing: border-box;
		width: 100%;
		min-height: 44px;
	}

	.row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem;
		margin-top: 0.75rem;
	}
</style>
