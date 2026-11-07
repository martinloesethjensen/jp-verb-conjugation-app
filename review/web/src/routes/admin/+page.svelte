<script lang="ts">
	import {
		addUser,
		ApiError,
		getInbox,
		FILES,
		getSnapshot,
		listUsers,
		beginLoad,
		finishLoad,
		loadSlice,
		setActive,
		setPublicRole,
		type DataFileName,
		type PublicRole,
		type SnapshotFile,
		type User
	} from '#lib/api.ts';
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

	// Published data: what is loaded, and the result of each file in the current load.
	let files = $state<SnapshotFile[]>([]);
	let loading = $state(false);
	let results = $state<Partial<Record<DataFileName, string>>>({});

	const loadedFile = (name: DataFileName) => files.find((f) => f.name === name);
	const when = (iso: string) => new Date(iso).toLocaleString();

	async function loadAll() {
		loading = true;
		results = {};
		for (const name of FILES) {
			results[name] = `Loading ${name}.json…`;
			try {
				const started = await beginLoad(name);
				for (let slice = 0; slice < started.slices; slice++) {
					results[name] = `Loading ${name}.json: ${slice + 1} of ${started.slices}`;
					await loadSlice(started.load_id, slice);
				}
				const snapshot = await finishLoad(started.load_id);
				files = [...files.filter((f) => f.name !== name), snapshot];
				results[name] = `Loaded ${snapshot.version}`;
			} catch (error) {
				results[name] = text(error);
				break;
			}
		}
		loading = false;
	}

	let openSuggestions = $state<number | null>(null);

	onMount(() => {
		getInbox('open')
			.then((list) => (openSuggestions = list.length))
			.catch(() => {});
		getSnapshot()
			.then((list) => (files = list))
			.catch(() => {});
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

	async function credit(user: User, role: PublicRole) {
		busy = true;
		notice = null;
		try {
			const updated = await setPublicRole(user.email, role);
			users = users.map((u) => (u.email === updated.email ? updated : u));
		} catch (error) {
			notice = text(error);
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
	<nav class="review-links" aria-label="Reviews">
		<a href="/admin/inbox">Suggestions{openSuggestions === null ? '' : ` (${openSuggestions} open)`}</a>
		<a href="/admin/queues">Queues</a>
	</nav>
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
								{#if user.public_role === 'owner'}
									<p class="credit">Credited as the owner</p>
								{:else}
									<label class="credit">
										<span>Credited as</span>
										<select
											value={user.public_role}
											disabled={busy}
											onchange={(e) => credit(user, e.currentTarget.value as PublicRole)}
										>
											<option value="teacher">a teacher</option>
											<option value="native">a native speaker</option>
										</select>
									</label>
								{/if}
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

	<section class="data" aria-labelledby="data-heading">
		<h2 id="data-heading">Published data</h2>
		<p class="hint">
			Loads the files on GitHub's main branch, checked against your signature. Do this after a data
			PR merges.
		</p>
		<table>
			<thead>
				<tr><th scope="col">File</th><th scope="col">Loaded</th><th scope="col">When</th></tr>
			</thead>
			<tbody>
				{#each FILES as name (name)}
					{@const file = loadedFile(name)}
					<tr>
						<td>{name}.json</td>
						<td>{file ? file.version : 'Not loaded'}</td>
						<td class="when">{file ? `${when(file.imported_at)} by ${file.imported_by}` : ''}</td>
					</tr>
					{#if results[name]}
						<tr class="result"><td colspan="3"><span role="status">{results[name]}</span></td></tr>
					{/if}
				{/each}
			</tbody>
		</table>
		<button class="primary" type="button" disabled={loading} onclick={loadAll}>Load published data</button>
	</section>
{/if}

<style>
	.review-links {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem;
		margin-bottom: 1.5rem;
	}

	.review-links a {
		padding: 0.6rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		text-decoration: none;
	}

	.review-links a:hover {
		border-color: var(--ink);
	}

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

	.data {
		margin-top: 2.5rem;
		max-width: 42rem;
	}

	.hint {
		color: var(--muted);
	}

	table {
		width: 100%;
		margin-bottom: 1rem;
		border-collapse: collapse;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	th,
	td {
		padding: 0.5rem 0.75rem;
		text-align: left;
		border-top: 1px solid var(--rule);
		overflow-wrap: anywhere;
	}

	th {
		font-weight: 500;
	}

	.when,
	.result td {
		color: var(--muted);
		font-size: 0.9rem;
	}

	.result td {
		border-top: none;
		padding-top: 0;
	}

	.credit {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin: 0.3rem 0 0;
		color: var(--muted);
		font-size: 0.9rem;
	}
</style>
