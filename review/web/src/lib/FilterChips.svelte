<script lang="ts">
	// A row of filter chips: one chosen at a time. The row scrolls sideways rather than wrapping.
	let {
		label,
		options,
		value = $bindable()
	}: {
		label: string;
		options: { value: string; label: string; count?: number }[];
		value: string;
	} = $props();
</script>

<div class="filter-chips" role="group" aria-label={label}>
	{#each options as option (option.value)}
		<button type="button" class="chip" aria-pressed={value === option.value} onclick={() => (value = option.value)}
			>{option.count === undefined ? option.label : `${option.label} ${option.count}`}</button
		>
	{/each}
</div>

<style>
	.filter-chips {
		display: flex;
		gap: 0.4rem;
		overflow-x: auto;
		scrollbar-width: none;
	}

	.filter-chips .chip {
		flex: none;
	}
</style>
