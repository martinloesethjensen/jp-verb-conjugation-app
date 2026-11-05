<script lang="ts">
	let { level }: { level: string | null | undefined } = $props();
</script>

{#if level}<span class="level">{level}</span>{/if}

<style>
	.level {
		padding: 0.05rem 0.5rem;
		border: 1px solid var(--rule);
		border-radius: 999px;
		font-size: 0.8rem;
		color: var(--muted);
		white-space: nowrap;
	}
</style>
