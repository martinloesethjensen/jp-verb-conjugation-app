<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import favicon from '#lib/assets/favicon.svg';
	import { ApiError, getMe, type Me } from '#lib/api.ts';
	import { afterNavigate } from '$app/navigation';
	import { replies } from '#lib/replies.svelte.ts';
	import { setSession } from '#lib/session.ts';
	import SiteHeader from '#lib/SiteHeader.svelte';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();

	let me = $state<Me | null>(null);
	let failure = $state<string | null>(null);
	// Show "Loading…" only if sign-in takes a moment, so a fast load doesn't flash it.
	let slow = $state(false);

	setSession({ me: () => me!, update: (user) => (me = user) });

	// Replies load with the site and again after each navigation: there is no push.
	afterNavigate(({ from }) => {
		if (me && from) replies.refresh();
	});

	onMount(() => {
		const timer = setTimeout(() => (slow = true), 300);
		getMe()
			.then((user) => {
				me = user;
				replies.refresh();
			})
			.catch((error) => {
				failure =
					error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.';
			})
			.finally(() => clearTimeout(timer));
		return () => clearTimeout(timer);
	});
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<title>Kotoba Table review</title>
</svelte:head>

<SiteHeader {me} />

<main>
	{#if failure}
		<p class="notice" role="alert">{failure}</p>
	{:else if me}
		{@render children()}
	{:else if slow}
		<p class="quiet">Loading…</p>
	{/if}
</main>

<style>
	main {
		max-width: 1120px;
		margin: 0 auto;
		padding: 3rem 1rem 4.5rem;
	}

	.quiet {
		color: var(--muted);
	}

	.notice {
		max-width: 34rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
