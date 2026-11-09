<script lang="ts">
	// The review actions for one target (an entry or one of its parts), with the seals of everyone who
	// approved it and the suggestions made on it.
	import { isStale, problem, type Field } from './api.ts';
	import ErrorLine from './ErrorLine.svelte';
	import Seal from './Seal.svelte';
	import SuggestForm from './SuggestForm.svelte';
	import SuggestionCard from './SuggestionCard.svelte';
	import type { EntryReview } from './review.svelte.ts';

	type Json = { [key: string]: any };

	let {
		review,
		kind,
		id,
		value,
		fields,
		readings,
		forms,
		extra = {},
		onaction,
		onskip
	}: {
		review: EntryReview;
		kind: string;
		id: string;
		/** The target as it is now. */
		value: Json;
		fields: Field[];
		readings: Record<string, string>;
		forms: Record<string, string>;
		extra?: Record<string, string>;
		/** Called after the viewer approves or suggests (the queue moves on). */
		onaction?: () => void;
		/** Offers "Not sure, skip" (queues only). */
		onskip?: () => Promise<void>;
	} = $props();

	const uid = $props.id();
	let mode = $state<'change' | 'delete' | 'note' | null>(null);
	let comment = $state('');
	let busy = $state(false);
	let failure = $state<string | null>(null);
	let stale = $state(false);

	const approvals = $derived(review.approvalsOf(kind, id));
	const suggestions = $derived(review.suggestionsOf(kind, id));
	const approved = $derived(review.approvedByMe(kind, id));
	const loaded = $derived(review.hashOf(kind, id) !== undefined);
	const names = $derived(fields.map((f) => f.name));

	async function run(action: () => Promise<unknown>, after?: () => void) {
		busy = true;
		failure = null;
		stale = false;
		try {
			await action();
			after?.();
		} catch (error) {
			failure = problem(error);
			stale = isStale(error);
		} finally {
			busy = false;
		}
	}

	function open(next: typeof mode) {
		mode = mode === next ? null : next;
		comment = '';
		failure = null;
	}

	const done = () => {
		mode = null;
		comment = '';
		onaction?.();
	};

	async function sendComment(event: SubmitEvent) {
		event.preventDefault();
		if (mode !== 'delete' && mode !== 'note') return;
		const action = mode;
		await run(() => review.suggest(kind, id, action, { comment: comment.trim() }), done);
	}
</script>

<div class="review-bar">
	{#if approvals.length}
		<div class="seals">
			{#each approvals.filter((a) => a.current) as a (a.reviewer_name)}
				<Seal name={a.reviewer_name} pressed={a.mine && review.isJustApproved(kind, id)} />
			{/each}
			{#each approvals.filter((a) => !a.current) as a (a.reviewer_name)}
				<span class="earlier">{a.reviewer_name} approved an earlier version</span>
			{/each}
		</div>
	{/if}

	{#if loaded}
		<div class="actions">
			{#if approved}
				<button type="button" class="approved" disabled>Approved</button>
				<button type="button" class="link" disabled={busy} onclick={() => run(() => review.undo(kind, id))}>Undo</button>
			{:else}
				<button type="button" class="primary" disabled={busy} onclick={() => run(() => review.approve(kind, id), onaction)}
					><svg class="icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5l3.2 3L13 4.5" /></svg>Looks right</button
				>
			{/if}
			{#if fields.length}
				<button type="button" aria-expanded={mode === 'change'} onclick={() => open('change')}
					><svg class="icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M10.5 2.5l3 3-8 8H2.5v-3z" /></svg>Suggest a change</button
				>
			{/if}
			<span class="spacer"></span>
			{#if onskip}
				<button type="button" class="link" disabled={busy} onclick={() => run(onskip)}>Not sure, skip</button>
			{/if}
			<button type="button" class="link" aria-expanded={mode === 'delete'} onclick={() => open('delete')}
				>Suggest removing it</button
			>
			<button type="button" class="link" aria-expanded={mode === 'note'} onclick={() => open('note')}
				>Leave a note</button
			>
		</div>
	{/if}

	{#if mode === 'change'}
		<SuggestForm
			{fields}
			current={value}
			{readings}
			{forms}
			{extra}
			onsubmit={async (edits, furigana) => {
				await review.suggest(kind, id, 'change', { edits, furigana: Object.keys(furigana).length ? furigana : undefined });
				done();
			}}
			oncancel={() => (mode = null)}
		/>
	{:else if mode === 'delete' || mode === 'note'}
		<form class="comment" onsubmit={sendComment}>
			<label for="{uid}-comment">{mode === 'delete' ? 'Why? (optional)' : 'Your note'}</label>
			<textarea id="{uid}-comment" rows="3" maxlength="2000" bind:value={comment}></textarea>
			<div class="buttons">
				<button class="primary small" disabled={busy || (mode === 'note' && !comment.trim())}>
					{mode === 'delete' ? 'Suggest removing it' : 'Send note'}
				</button>
				<button type="button" class="link" onclick={() => (mode = null)}>Cancel</button>
			</div>
		</form>
	{/if}
	<ErrorLine message={failure} {stale} />

	{#each suggestions as s (s.id)}
		<SuggestionCard
			suggestion={s}
			current={value}
			{names}
			onwithdraw={() => review.withdraw(s.id)}
			oncomment={(text) => review.comment(s.id, text)}
		/>
	{/each}
</div>

<style>
	.review-bar {
		margin: 0.4rem 0 0.25rem;
	}

	.seals {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem 0.75rem;
		align-items: center;
		margin-bottom: 0.4rem;
	}

	.earlier {
		font-size: 0.85rem;
		color: var(--muted);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem 0.75rem;
		align-items: center;
		margin-top: 1.25rem;
		padding-top: 1.25rem;
		border-top: 1px solid var(--rule);
	}

	.spacer {
		flex: 1 1 0;
	}

	.icon {
		width: 16px;
		height: 16px;
		fill: none;
		stroke: currentColor;
		stroke-width: 1.8;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	.approved:disabled {
		opacity: 1;
		background: var(--red-soft);
		border-color: var(--red);
		color: var(--red);
	}

	.comment {
		display: grid;
		gap: 0.3rem;
		margin-top: 0.6rem;
	}

	label {
		font-size: 0.9rem;
	}

	.buttons {
		display: flex;
		gap: 0.75rem;
		align-items: center;
	}
</style>
