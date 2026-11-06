<script lang="ts">
	// A failed action's message under a form. A conflict (the item changed) offers a reload.
	let { message, stale = false }: { message: string | null; stale?: boolean } = $props();
</script>

{#if message}
	<p class="error" role="alert">
		{message}
		{#if stale}<button type="button" class="small" onclick={() => location.reload()}>Reload</button>{/if}
	</p>
{/if}

<style>
	.error {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem;
		margin: 0.5rem 0 0;
		color: var(--red);
	}
</style>
