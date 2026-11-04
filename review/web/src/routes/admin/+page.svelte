<script lang="ts">
	import { addUser, ApiError, listUsers, setActive, type User } from '#lib/api.ts';
	import { getSession } from '#lib/session.ts';
	import { onMount } from 'svelte';

	const { me } = getSession();

	let users = $state<User[]>([]);
	let loaded = $state(false);
	let failure = $state<string | null>(null);
	let notice = $state<string | null>(null);
	let formError = $state<string | null>(null);
	let email = $state('');
	let displayName = $state('');
	let busy = $state(false);

	function text(error: unknown) {
		return error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.';
	}

	onMount(() => {
		listUsers()
			.then((list) => {
				users = list;
				loaded = true;
			})
			.catch((error) => (failure = text(error)));
	});

	async function add(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		formError = null;
		notice = null;
		try {
			const user = await addUser(email, displayName);
			users = [...users, user].sort((a, b) => a.display_name.localeCompare(b.display_name));
			notice = `Added ${user.display_name}. Also add ${user.email} to the Access allow-list in Cloudflare, or they can't sign in.`;
			email = '';
			displayName = '';
		} catch (error) {
			formError = text(error);
		} finally {
			busy = false;
		}
	}

	async function toggle(user: User) {
		busy = true;
		notice = null;
		try {
			const updated = await setActive(user.email, !user.active);
			users = users.map((u) => (u.email === updated.email ? updated : u));
		} catch (error) {
			notice = text(error);
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>Reviewers · Kotoba Table review</title>
</svelte:head>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else}
	<div class="columns">
		<section aria-labelledby="reviewers-heading">
			<h1 id="reviewers-heading">Reviewers</h1>
			{#if !loaded}
				<p class="quiet">Loading…</p>
			{:else}
				<ul class="people">
					{#each users as user (user.email)}
						<li class={{ inactive: !user.active }}>
							<div>
								<p class="person">{user.display_name}</p>
								<p class="email">{user.email}</p>
							</div>
							<div class="state">
								<span class={['pill', user.active ? 'active' : 'inactive']}>
									{user.active ? 'Active' : 'Inactive'}
								</span>
								{#if user.email !== me().email}
									<button
										type="button"
										class={{ danger: user.active }}
										disabled={busy}
										onclick={() => toggle(user)}
									>
										{user.active ? 'Deactivate' : 'Reactivate'}
									</button>
								{/if}
							</div>
						</li>
					{/each}
				</ul>
			{/if}
			{#if notice}
				<p class="notice" role="status">{notice}</p>
			{/if}
		</section>

		<section class="add" aria-labelledby="add-heading">
			<h2 id="add-heading">Add a reviewer</h2>
			<form onsubmit={add}>
				<label>
					<span>Email</span>
					<input type="email" bind:value={email} required autocomplete="off" />
				</label>
				<label>
					<span>Display name</span>
					<input type="text" bind:value={displayName} required maxlength="40" autocomplete="off" />
				</label>
				{#if formError}
					<p class="error" role="alert">{formError}</p>
				{/if}
				<button class="primary" type="submit" disabled={busy}>Add reviewer</button>
			</form>
		</section>
	</div>
{/if}

<style>
	h1,
	h2 {
		margin-top: 0;
		font-weight: 500;
	}

	h1 {
		font-size: 1.5rem;
	}

	h2 {
		font-size: 1.15rem;
	}

	.columns {
		display: grid;
		grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
		gap: 2.5rem;
		align-items: start;
	}

	@media (max-width: 720px) {
		.columns {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	.people {
		list-style: none;
		margin: 0;
		padding: 0;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.people li {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem 1rem;
		padding: 0.85rem 1rem;
	}

	.people li + li {
		border-top: 1px solid var(--rule);
	}

	.people p {
		margin: 0;
	}

	.person {
		font-weight: 500;
	}

	.email,
	.quiet {
		color: var(--muted);
		overflow-wrap: anywhere;
	}

	.inactive .person {
		color: var(--muted);
	}

	.pill {
		padding: 0.1rem 0.65rem;
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 500;
	}

	.pill.active {
		background: var(--green-soft);
		color: var(--green);
	}

	.pill.inactive {
		background: var(--rule);
		color: var(--muted);
	}

	.state {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.add {
		padding: 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	form {
		display: grid;
		gap: 0.9rem;
	}

	label {
		display: grid;
		gap: 0.3rem;
	}

	form button {
		justify-self: start;
	}

	.notice {
		margin-top: 1rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.error {
		margin: 0;
	}
</style>
