<script lang="ts">
	// A queue's progress: done in ink, items with an open suggestion in red after it. Drawn as SVG
	// attributes because the CSP allows no inline styles.
	let { total, done, flagged = 0 }: { total: number; done: number; flagged?: number } = $props();

	const part = (n: number) => (total > 0 ? Math.min(100, (n / total) * 100) : 0);
	const doneWidth = $derived(part(done));
	const flaggedWidth = $derived(Math.min(part(flagged), 100 - doneWidth));
</script>

<svg class="progress" viewBox="0 0 100 4" preserveAspectRatio="none" role="img" aria-label="{done} of {total} done">
	<rect class="track" width="100" height="4" />
	<rect class="done" width={doneWidth} height="4" />
	<rect class="flagged" x={doneWidth} width={flaggedWidth} height="4" />
</svg>

<style>
	.progress {
		display: block;
		width: 100%;
		height: 8px;
		border-radius: 4px;
		overflow: hidden;
	}

	.track {
		fill: var(--rule);
	}

	.done {
		fill: var(--ink);
	}

	.flagged {
		fill: var(--red);
	}
</style>
