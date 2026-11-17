<script lang="ts">
	// The first thing a new reviewer sees on a computer. Start leaves the tour for their first queue.
	let { open, onstart, onskip }: { open: boolean; onstart: () => void; onskip: () => void } = $props();

	let dialog = $state<HTMLDialogElement>();
	$effect(() => {
		if (!dialog) return;
		if (open && !dialog.open) dialog.showModal();
		else if (!open && dialog.open) dialog.close();
	});
</script>

<dialog class="welcome" bind:this={dialog} aria-labelledby="welcome-title" oncancel={(e) => (e.preventDefault(), onskip())}>
	<h2 id="welcome-title">Welcome to Kotoba Table review</h2>
	<p>You help make the app's Japanese right. A short tour shows you around the first time you open a queue.</p>
	<div class="actions">
		<button type="button" class="primary" onclick={onstart}>Start</button>
		<button type="button" class="link" onclick={onskip}>Skip the tour</button>
	</div>
</dialog>

<style>
	.welcome {
		width: min(28rem, calc(100vw - 2rem));
		padding: 1.75rem;
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		background: var(--card);
		color: var(--ink);
	}

	.welcome::backdrop {
		background: rgb(30 38 51 / 0.35);
	}

	h2 {
		margin-top: 0;
		font-weight: 500;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 1rem;
		margin-top: 1.5rem;
	}

	.actions button {
		min-height: 44px;
	}
</style>
