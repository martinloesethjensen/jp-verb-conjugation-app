<script lang="ts">
	// The "Ask for a second opinion" panel under an item's open suggestions: pick a colleague, add a question,
	// ask. They see both suggestions and pick one, or say why neither works; the asker still decides.
	import { onMount, untrack } from 'svelte';
	import { askOpinion, getCandidates, problem, type Candidate, type Target } from './api.ts';
	import ErrorLine from './ErrorLine.svelte';
	import { askLabel, firstCandidate, seenNote } from './opinions.ts';

	let {
		target,
		onasked,
		candidates: given = null,
		error = null
	}: {
		target: Target;
		onasked: () => void;
		/** The people who can be asked; loaded when not given (the given list is for tests). */
		candidates?: Candidate[] | null;
		/** A message to start with (for tests). */
		error?: string | null;
	} = $props();

	const uid = $props.id();
	// The given list and message only seed the state.
	let candidates = $state<Candidate[] | null>(untrack(() => given));
	let chosen = $state<number | null>(untrack(() => (given ? firstCandidate(given) : null)));
	let question = $state('');
	let busy = $state(false);
	let failure = $state<string | null>(untrack(() => error));

	onMount(async () => {
		if (candidates) return;
		try {
			candidates = await getCandidates(target);
			chosen = firstCandidate(candidates);
		} catch (e) {
			candidates = [];
			failure = problem(e);
		}
	});

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

{#if candidates === null || candidates.length || failure}
	<form class="ask" onsubmit={ask} aria-labelledby="{uid}-heading">
		<h3 id="{uid}-heading">Ask for a second opinion</h3>
		<p class="lead">They see both suggestions and pick one, or say why neither works. You still decide.</p>
		{#if candidates === null}
			<p class="lead">Loading…</p>
		{:else if candidates.length}
			<div class="people" role="radiogroup" aria-label="Who to ask">
				{#each candidates as c (c.user)}
					<button
						type="button"
						role="radio"
						class="person"
						aria-checked={chosen === c.user}
						onclick={() => (chosen = c.user)}
					>
						<span class="initial" aria-hidden="true">{(Array.from(c.name.trim())[0] ?? '?').toUpperCase()}</span>
						<span class="who"
							><span class="name">{c.name}</span><span class="note">{c.role} · {seenNote(c)}</span></span
						>
					</button>
				{/each}
			</div>
			<label for="{uid}-question">Your question (optional)</label>
			<input id="{uid}-question" type="text" bind:value={question} autocomplete="off" />
			<div class="row">
				<button type="submit" class="primary" disabled={busy || chosen === null}>{askLabel(candidates, chosen)}</button>
			</div>
		{/if}
		<ErrorLine message={failure} />
	</form>
{/if}

<style>
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
		margin-top: 0.75rem;
	}
</style>
