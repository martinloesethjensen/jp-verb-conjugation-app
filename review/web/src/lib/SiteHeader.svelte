<script lang="ts">
	import type { Me } from './api.ts';

	let { me }: { me: Me | null } = $props();

	const initial = $derived(me ? (Array.from(me.display_name.trim())[0] ?? '?').toUpperCase() : '');
</script>

<header class="bar">
	<div class="inner">
		<!-- Full page loads between the reviewer and admin pages: they sit behind different Access sign-ins. -->
		<a class="name" href="/" data-sveltekit-reload>
			<span class="mark" lang="ja"><ruby>添削<rt>てんさく</rt></ruby></span>
			<span class="title">Kotoba Table <span class="sub">review</span></span>
		</a>
		{#if me}
			<nav class="links" aria-label="Account">
				{#if me.role === 'admin'}
					<a href="/admin" data-sveltekit-reload>Reviewers</a>
				{/if}
				<a class="who" href="/account" title="Change your name">
					<span class="initial" aria-hidden="true">{initial}</span>
					<span class="who-name">{me.display_name}</span>
				</a>
				<!-- Cloudflare Access's own endpoint: ends the sign-in for this hostname (reviewer and admin). -->
				<a href="/cdn-cgi/access/logout" data-sveltekit-reload>Sign out</a>
			</nav>
			<details class="account-menu">
				<summary aria-label="Account: {me.display_name}">
					<span class="initial" aria-hidden="true">{initial}</span>
				</summary>
				<div class="panel">
					<p class="panel-name">{me.display_name}</p>
					<a href="/account">Your name</a>
					{#if me.role === 'admin'}
						<a href="/admin" data-sveltekit-reload>Reviewers</a>
					{/if}
					<a href="/cdn-cgi/access/logout" data-sveltekit-reload>Sign out</a>
				</div>
			</details>
		{/if}
	</div>
</header>

<style>
	.bar {
		background: var(--card);
		border-bottom: 1px solid var(--rule);
	}

	.inner {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		max-width: 1120px;
		min-height: 64px;
		margin: 0 auto;
		padding: 0.5rem 1rem;
	}

	.name {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		min-width: 0;
		text-decoration: none;
	}

	.mark {
		flex: none;
		padding: 0.1rem 0.45rem 0.15rem;
		border: 1.5px solid var(--red);
		border-radius: 8px;
		background: var(--red-soft);
		color: var(--red);
		font-size: 1.15rem;
		font-weight: 700;
		line-height: 1.5;
		transform: rotate(-4deg);
	}

	.mark :global(rt) {
		font-size: 0.5em;
		font-weight: 500;
	}

	.title {
		font-weight: 700;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.sub {
		font-weight: 400;
		color: var(--muted);
	}

	.links {
		display: flex;
		align-items: center;
		gap: 1.25rem;
	}

	.links a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
	}

	.who {
		gap: 0.5rem;
		text-decoration: none;
	}

	.who:hover .who-name {
		text-decoration: underline;
	}

	.who-name {
		max-width: 12rem;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.initial {
		display: inline-grid;
		place-items: center;
		flex: none;
		width: 32px;
		height: 32px;
		border-radius: 50%;
		background: var(--ink);
		color: var(--card);
		font-size: 0.9rem;
		font-weight: 700;
	}

	.account-menu {
		display: none;
		position: relative;
	}

	.account-menu summary {
		display: grid;
		place-items: center;
		width: 44px;
		height: 44px;
		list-style: none;
		cursor: pointer;
		border-radius: 999px;
	}

	.account-menu summary::-webkit-details-marker {
		display: none;
	}

	.panel {
		position: absolute;
		right: 0;
		top: calc(100% + 0.4rem);
		z-index: 10;
		display: flex;
		flex-direction: column;
		width: min(16rem, calc(100vw - 2rem));
		padding: 0.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		box-shadow: 0 8px 24px rgb(30 38 51 / 0.12);
	}

	.panel-name {
		margin: 0;
		padding: 0.5rem 0.75rem;
		font-weight: 700;
		overflow-wrap: anywhere;
		border-bottom: 1px solid var(--rule);
	}

	.panel a {
		display: flex;
		align-items: center;
		min-height: 44px;
		padding: 0 0.75rem;
		border-radius: var(--radius-input);
		text-decoration: none;
	}

	.panel a:hover {
		background: var(--well);
	}

	@media (max-width: 720px) {
		.links {
			display: none;
		}

		.account-menu {
			display: block;
		}
	}
</style>
