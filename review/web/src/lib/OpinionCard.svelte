<script lang="ts">
	// A second-opinion request on the item page. The person asked sees the open suggestions and picks one, or
	// says why neither works; anyone else sees where the request stands. It sits above the oldest suggestion's thread.
	import { answerOpinion, problem, type Opinion, type Suggestion } from './api.ts';
	import ErrorLine from './ErrorLine.svelte';
	import Japanese from './Japanese.svelte';
	import { KINDS } from './labels.ts';
	import { answeredLine, canAnswer, cardMode, NEITHER, pickable, stepIndex, waitingLine } from './opinions.ts';
	import RedPen from './RedPen.svelte';
	import { replies } from './replies.svelte.ts';

	type Json = { [key: string]: any };

	let {
		opinion,
		suggestions,
		current = null,
		names = [],
		readings = {},
		onanswered
	}: {
		opinion: Opinion;
		/** The item's suggestions; the open changes are what the asked person chooses between. */
		suggestions: Suggestion[];
		/** The target as it is now, for the red-pen summaries. */
		current?: Json | null;
		names?: string[];
		readings?: Record<string, string>;
		onanswered: () => Promise<void> | void;
	} = $props();

	const uid = $props.id();
	const mode = $derived(cardMode(opinion));
	const options = $derived(pickable(suggestions));
	const picked = $derived(suggestions.find((s) => s.id === opinion.pick)?.author_name ?? null);
	let pick = $state<number | typeof NEITHER | null>(null);
	let body = $state('');
	let busy = $state(false);
	let failure = $state<string | null>(null);
	let group = $state<HTMLElement>();

	// The values a radio can take, in order: each open suggestion, then Neither.
	const values = $derived<(number | typeof NEITHER)[]>([...options.map((s) => s.id), NEITHER]);

	// A reload can take the picked suggestion out of the open list.
	$effect(() => {
		if (pick !== null && !values.includes(pick)) pick = null;
	});

	// Seeing the request reads its thread: the bell's count for it clears, once the replies are in.
	let marked = false;
	$effect(() => {
		if (marked || !replies.loaded) return;
		if (replies.list.some((r) => r.suggestion_id === opinion.anchor_id && r.unread)) {
			marked = true;
			replies.read(opinion.anchor_id);
		}
	});

	function key(event: KeyboardEvent) {
		const delta = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0;
		if (!delta) return;
		event.preventDefault();
		const next = stepIndex(pick === null ? -1 : values.indexOf(pick), delta, values.length);
		pick = values[next];
		group?.querySelectorAll<HTMLElement>('[role="radio"]')[next]?.focus();
	}

	async function send(event: SubmitEvent) {
		event.preventDefault();
		if (!canAnswer(pick, body) || busy || pick === null) return;
		busy = true;
		failure = null;
		try {
			await answerOpinion(opinion.id, pick === NEITHER ? null : pick, body.trim());
			await onanswered();
		} catch (e) {
			failure = problem(e);
		} finally {
			busy = false;
		}
	}
</script>

{#snippet question()}
	{#if opinion.question}<p class="question"><Japanese text={opinion.question} {readings} prose /></p>{/if}
{/snippet}

{#if mode === 'answer'}
	<form class="opinion" onsubmit={send} aria-labelledby="{uid}-heading">
		<h3 id="{uid}-heading">{opinion.asked_by_name} asked for your opinion</h3>
		{@render question()}
		<div class="options" role="radiogroup" aria-label="Which suggestion is better?" bind:this={group}>
			{#each options as s, i (s.id)}
				<button
					type="button"
					role="radio"
					class="option"
					aria-checked={pick === s.id}
					tabindex={pick === s.id || (pick === null && i === 0) ? 0 : -1}
					onclick={() => (pick = s.id)}
					onkeydown={key}
				>
					<span class="author">{s.author_name}</span>
					{#if s.action === 'change' && s.proposed}
						<RedPen before={current ?? {}} after={s.proposed} names={names.length ? names : Object.keys(s.proposed)} />
					{:else if s.action === 'delete'}
						<span class="gist">Remove this {KINDS[s.kind] ?? s.kind}</span>
					{:else}
						<span class="gist">Add a new {KINDS[s.kind] ?? s.kind}</span>
					{/if}
				</button>
			{/each}
			<button
				type="button"
				role="radio"
				class="option"
				aria-checked={pick === NEITHER}
				tabindex={pick === NEITHER || (pick === null && options.length === 0) ? 0 : -1}
				onclick={() => (pick = NEITHER)}
				onkeydown={key}
			>
				<span class="author">Neither</span>
				<span class="gist">Say why in the box below</span>
			</button>
		</div>
		<label for="{uid}-body">{pick === NEITHER ? 'Why neither works' : 'Why? (optional)'}</label>
		<textarea id="{uid}-body" rows="3" maxlength="2000" bind:value={body}></textarea>
		<div class="row">
			<button type="submit" class="primary" disabled={busy || !canAnswer(pick, body)}>Send</button>
		</div>
		<ErrorLine message={failure} />
	</form>
{:else if mode === 'decided'}
	<div class="opinion">
		<p class="line">Already decided. Thanks anyway.</p>
	</div>
{:else if mode === 'status'}
	<div class="opinion">
		{#if opinion.answered_at}
			<p class="line"><strong>{answeredLine(opinion, picked)}</strong></p>
			{#if opinion.answer}<p class="muted"><Japanese text={opinion.answer} {readings} prose /></p>{/if}
		{:else}
			<p class="line"><strong>{waitingLine(opinion)}</strong></p>
			{@render question()}
		{/if}
	</div>
{/if}

<style>
	.opinion {
		margin-top: 0.75rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	h3 {
		margin: 0 0 0.5rem;
		font-size: 1rem;
	}

	.line {
		margin: 0;
	}

	.muted {
		margin: 0.25rem 0 0;
		font-size: 0.9rem;
		color: var(--muted);
	}

	.question {
		margin: 0 0 0.75rem;
		padding: 0.5rem 0.75rem;
		background: var(--paper);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.options {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-bottom: 0.9rem;
	}

	.option {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.25rem;
		min-height: 52px;
		padding: 0.5rem 0.75rem;
		text-align: left;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.option[aria-checked='true'] {
		border: 2px solid var(--ink);
	}

	.author {
		font-weight: 600;
	}

	.gist {
		font-size: 0.9rem;
		color: var(--muted);
	}

	label {
		display: block;
		margin-bottom: 0.25rem;
		font-size: 0.9rem;
	}

	textarea {
		box-sizing: border-box;
		width: 100%;
	}

	.row {
		margin-top: 0.75rem;
	}
</style>
