<script lang="ts">
	// What a second-opinion request says on an item: still waiting (with a way to cancel it for whoever asked),
	// or answered (who picked which suggestion, or that neither works, and why).
	import type { InboxSuggestion, Opinion } from './api.ts';
	import { answeredLine, askedLine, waitingLine } from './opinions.ts';

	let {
		opinion,
		suggestions,
		oncancel
	}: { opinion: Opinion; suggestions: InboxSuggestion[]; oncancel: () => void } = $props();

	const picked = $derived(suggestions.find((s) => s.id === opinion.pick)?.author_name ?? null);
	const answered = $derived(opinion.answered_at !== null);
</script>

<div class="status">
	{#if answered}
		<p class="line"><strong>{answeredLine(opinion, picked)}</strong></p>
		{#if opinion.answer}<p class="muted">{opinion.answer}</p>{/if}
	{:else}
		<p class="line"><span class="ring" aria-hidden="true"></span><strong>{waitingLine(opinion)}</strong></p>
		<p class="muted">{askedLine(opinion, suggestions)}</p>
		{#if opinion.question}<p class="muted">“{opinion.question}”</p>{/if}
		{#if opinion.mine_asked}
			<button type="button" class="link" onclick={oncancel}>Cancel the request</button>
		{/if}
	{/if}
</div>

<style>
	.status {
		margin-top: 1rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.line {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		margin: 0 0 0.25rem;
	}

	.ring {
		flex: none;
		width: 12px;
		height: 12px;
		box-sizing: border-box;
		border: 2px solid var(--ink);
		border-radius: 50%;
	}

	.muted {
		margin: 0 0 0.5rem;
		font-size: 0.9rem;
		color: var(--muted);
	}

	.link {
		min-height: 44px;
		color: var(--muted);
		text-decoration: underline;
	}
</style>
