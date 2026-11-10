<script lang="ts">
	// The header bell: a red count of new replies. Desktop opens a panel of the newest; phones go to /replies.
	import { afterNavigate } from '$app/navigation';
	import { replies } from './replies.svelte.ts';
	import ReplyList from './ReplyList.svelte';

	let open = $state(false);
	let panel = $state<HTMLDetailsElement>();
	afterNavigate(() => (open = false));

	const label = $derived(replies.unread ? `Replies, ${replies.unread} new` : 'Replies');
	const fresh = $derived(replies.list.filter((r) => r.unread).slice(0, 8));

	function onpointerdown(event: PointerEvent) {
		if (open && panel && !panel.contains(event.target as Node)) open = false;
	}
</script>

<svelte:window {onpointerdown} onkeydown={(e) => e.key === 'Escape' && (open = false)} />

{#snippet bell()}
	<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
		<path
			d="M12 3a6 6 0 0 0-6 6v3.5L4.5 16h15L18 12.5V9a6 6 0 0 0-6-6Zm-2 15a2 2 0 0 0 4 0"
			fill="none"
			stroke="currentColor"
			stroke-width="1.6"
			stroke-linejoin="round"
		/>
	</svg>
	{#if replies.unread}<span class="count">{replies.unread}</span>{/if}
{/snippet}

<details class="bell desktop" bind:open bind:this={panel}>
	<summary aria-label={label}>{@render bell()}</summary>
	<div class="bell-panel">
		<p class="heading">Replies</p>
		{#if fresh.length}
			<ReplyList replies={fresh} readings={replies.readings} />
			<button type="button" class="link" onclick={() => replies.readAll()}>Mark all read</button>
		{:else}
			<p class="quiet">Nothing new.</p>
		{/if}
		<a class="all" href="/replies">See all replies</a>
	</div>
</details>
<a class="bell phone" href="/replies" aria-label={label}>{@render bell()}</a>

<style>
	.bell {
		position: relative;
	}

	summary,
	.phone {
		position: relative;
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		list-style: none;
		cursor: pointer;
		border-radius: 999px;
		color: var(--ink);
	}

	summary::-webkit-details-marker {
		display: none;
	}

	.count {
		position: absolute;
		top: 4px;
		right: 2px;
		min-width: 1.15rem;
		padding: 0 0.3rem;
		border-radius: 999px;
		background: var(--red);
		color: var(--card);
		font-size: 0.72rem;
		font-weight: 700;
		line-height: 1.15rem;
		text-align: center;
	}

	.bell-panel {
		position: absolute;
		right: 0;
		top: calc(100% + 0.4rem);
		z-index: 10;
		width: min(22rem, calc(100vw - 2rem));
		max-height: 70vh;
		overflow-y: auto;
		padding: 0.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		box-shadow: 0 8px 24px rgb(30 38 51 / 0.12);
	}

	.heading {
		margin: 0;
		padding: 0.5rem 0.75rem;
		font-weight: 700;
		border-bottom: 1px solid var(--rule);
	}

	.quiet {
		margin: 0;
		padding: 0.75rem;
		color: var(--muted);
	}

	.link,
	.all {
		display: flex;
		align-items: center;
		min-height: 44px;
		padding: 0 0.75rem;
	}

	.phone {
		display: none;
	}

	@media (max-width: 720px) {
		.desktop {
			display: none;
		}

		.phone {
			display: grid;
		}
	}
</style>
