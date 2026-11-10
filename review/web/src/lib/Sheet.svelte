<script lang="ts">
	// A sheet over the page: a native modal <dialog>, so focus stays inside and Esc works. "bottom" rises
	// from the bottom edge (lists, menus); "full" covers the screen (forms on a phone). The parent owns
	// `open`; Esc, the backdrop and Cancel ask it to close through `onclose`.
	import type { Snippet } from 'svelte';

	let {
		open,
		title,
		variant = 'bottom',
		onclose,
		children
	}: {
		open: boolean;
		title: string;
		variant?: 'bottom' | 'full';
		onclose: () => void;
		children: Snippet;
	} = $props();

	const uid = $props.id();
	let dialog = $state<HTMLDialogElement>();

	$effect(() => {
		if (!dialog) return;
		if (open && !dialog.open) dialog.showModal();
		else if (!open && dialog.open) dialog.close();
	});

	function oncancel(event: Event) {
		event.preventDefault();
		onclose();
	}

	/** The browser closed the dialog itself (Android back, a repeated Esc): tell the parent, or its
	 *  `open` stays true and the next attempt to open the sheet does nothing. */
	function onDialogClose() {
		if (open) onclose();
	}

	/** A click on the dialog itself (not its content) is a click on the backdrop. */
	function onclick(event: MouseEvent) {
		if (event.target === dialog) onclose();
	}
</script>

<dialog bind:this={dialog} class={['sheet', variant]} aria-labelledby="{uid}-title" {oncancel} {onclick} onclose={onDialogClose}>
	<div class="inner">
		{#if variant === 'full'}
			<header class="top">
				<button type="button" class="link" onclick={onclose}>Cancel</button>
				<h2 id="{uid}-title">{title}</h2>
				<span class="balance" aria-hidden="true"></span>
			</header>
		{:else}
			<span class="grab" aria-hidden="true"></span>
			<h2 id="{uid}-title">{title}</h2>
		{/if}
		<div class="content">{@render children()}</div>
	</div>
</dialog>

<style>
	.sheet {
		margin: 0;
		padding: 0;
		border: none;
		max-width: none;
		background: var(--card);
		color: var(--ink);
	}

	.sheet::backdrop {
		background: rgb(30 38 51 / 0.35);
	}

	.sheet[open] {
		animation: sheet-up 220ms ease-out;
	}

	.bottom {
		inset: auto 0 0 0;
		width: 100%;
		max-height: 85dvh;
		border-radius: var(--radius) var(--radius) 0 0;
	}

	.full {
		inset: 0;
		width: 100%;
		height: 100dvh;
		max-height: none;
	}

	.inner {
		display: flex;
		flex-direction: column;
		max-height: inherit;
		height: 100%;
	}

	.bottom .inner {
		max-height: 85dvh;
		padding: 0.5rem 16px calc(1rem + env(safe-area-inset-bottom));
	}

	.grab {
		align-self: center;
		width: 36px;
		height: 4px;
		margin: 0.25rem 0 0.75rem;
		border-radius: 2px;
		background: var(--rule);
	}

	h2 {
		margin: 0 0 0.75rem;
		font-size: 1.15rem;
		font-weight: 700;
	}

	.top {
		display: grid;
		grid-template-columns: 1fr auto 1fr;
		align-items: center;
		padding: 0 16px;
		border-bottom: 1px solid var(--rule);
	}

	.top h2 {
		margin: 0;
		text-align: center;
	}

	.top .link {
		justify-self: start;
	}

	.content {
		flex: 1 1 auto;
		min-height: 0;
		overflow-y: auto;
		overscroll-behavior: contain;
	}

	.full .content {
		padding: 1rem 16px calc(1.5rem + env(safe-area-inset-bottom));
	}
</style>
