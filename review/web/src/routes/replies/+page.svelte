<script lang="ts">
	// Every recent reply in the threads you're part of: new ones first, then earlier ones.
	import { onMount } from 'svelte';
	import { groupReplies, replies } from '#lib/replies.svelte.ts';
	import ReplyList from '#lib/ReplyList.svelte';
	import { loadReference } from '#lib/reference.ts';

	let readings = $state<Record<string, string>>({});
	onMount(() => {
		replies.refresh();
		loadReference().then((reference) => (readings = reference.readings));
	});

	const groups = $derived(groupReplies(replies.list));
</script>

<svelte:head>
	<title>Replies · Kotoba Table review</title>
</svelte:head>

<h1>Replies</h1>

{#if !replies.list.length}
	<p class="quiet">No replies yet. When someone answers your suggestion or note, it shows up here.</p>
{:else}
	{#if groups.fresh.length}
		<section aria-labelledby="new-heading">
			<div class="head">
				<h2 id="new-heading">New</h2>
				<button type="button" class="link" onclick={() => replies.readAll()}>Mark all read</button>
			</div>
			<ReplyList replies={groups.fresh} {readings} />
		</section>
	{/if}
	{#if groups.earlier.length}
		<section aria-labelledby="earlier-heading">
			<h2 id="earlier-heading">Earlier</h2>
			<ReplyList replies={groups.earlier} {readings} />
		</section>
	{/if}
{/if}

<style>
	section {
		margin-top: 1.5rem;
		padding: 0.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	h2 {
		margin: 0.5rem 0.75rem;
		font-size: 1.25rem;
	}

	.link {
		min-height: 44px;
	}

	.quiet {
		color: var(--muted);
	}
</style>
