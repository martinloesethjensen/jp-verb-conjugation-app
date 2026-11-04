<script lang="ts">
	import '../app.css';
	import { onMount } from 'svelte';
	import favicon from '#lib/assets/favicon.svg';
	import { ApiError, getMe, type Me } from '#lib/api.ts';
	import { setSession } from '#lib/session.ts';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();

	let me = $state<Me | null>(null);
	let failure = $state<string | null>(null);
	// Show "Loading…" only if sign-in takes a moment, so a fast load doesn't flash it.
	let slow = $state(false);

	setSession({ me: () => me!, update: (user) => (me = user) });

	onMount(() => {
		const timer = setTimeout(() => (slow = true), 300);
		getMe()
			.then((user) => (me = user))
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

<header class="bar">
	<!-- Full page loads between the reviewer and admin pages: they sit behind different Access sign-ins. -->
	<a class="name" href="/" data-sveltekit-reload>
		<span class="mark" lang="ja">添削</span>
		<span>Kotoba Table review</span>
	</a>
	{#if me}
		<nav>
			{#if me.role === 'admin'}
				<a href="/admin" data-sveltekit-reload>Reviewers</a>
			{/if}
			<a class="who" href="/account" title="Change your name">{me.display_name}</a>
			<!-- Cloudflare Access's own endpoint: ends the sign-in for this hostname (reviewer and admin). -->
			<a href="/cdn-cgi/access/logout" data-sveltekit-reload>Sign out</a>
		</nav>
	{/if}
</header>

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
	.bar {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		justify-content: space-between;
		gap: 0.5rem 1.5rem;
		max-width: 60rem;
		margin: 0 auto;
		padding: 1.25rem var(--space);
		border-bottom: 1px solid var(--rule);
	}

	.name {
		display: flex;
		align-items: baseline;
		gap: 0.6rem;
		text-decoration: none;
		font-weight: 500;
	}

	.mark {
		font-size: 1.4rem;
		font-weight: 700;
		letter-spacing: 0.05em;
	}

	nav {
		display: flex;
		align-items: baseline;
		gap: 1.25rem;
	}

	.who {
		color: var(--muted);
		text-decoration: none;
	}

	.who:hover {
		color: var(--ink);
		text-decoration: underline;
	}

	main {
		max-width: 60rem;
		margin: 0 auto;
		padding: 2rem var(--space) 4rem;
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
