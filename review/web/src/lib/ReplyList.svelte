<script lang="ts">
	// Replies as links to their threads: who did what, on which item, and when.
	import type { Reply } from './api.ts';
	import { shortDate } from './dates.ts';
	import Japanese from './Japanese.svelte';
	import { replyText } from './replies.svelte.ts';
	import { suggestionHref } from './targets.ts';

	let { replies, readings }: { replies: Reply[]; readings: Record<string, string> } = $props();
</script>

<ul class="replies">
	{#each replies as r (`${r.suggestion_id}/${r.what}/${r.at}`)}
		<li>
			<a href={suggestionHref(r)} class={{ unread: r.unread }}>
				<span class="what">{replyText(r)}</span>
				<span class="on">on <Japanese text={r.item_title} {readings} /></span>
				{#if r.body}<span class="body">“{r.body}”</span>{/if}
				<time datetime={r.at}>{shortDate(new Date(r.at))}</time>
			</a>
		</li>
	{/each}
</ul>

<style>
	.replies {
		list-style: none;
		margin: 0;
		padding: 0;
	}

	a {
		display: grid;
		gap: 0.15rem;
		min-height: 44px;
		padding: 0.6rem 0.75rem;
		border-radius: var(--radius-input);
		text-decoration: none;
		color: var(--ink);
	}

	a:hover {
		background: var(--well);
	}

	.what {
		font-weight: 700;
	}

	.unread .what::before {
		content: '';
		display: inline-block;
		width: 0.5rem;
		height: 0.5rem;
		margin-right: 0.4rem;
		border-radius: 999px;
		background: var(--red);
		vertical-align: middle;
	}

	.on,
	.body,
	time {
		color: var(--muted);
		font-size: 0.9rem;
		overflow-wrap: anywhere;
	}
</style>
