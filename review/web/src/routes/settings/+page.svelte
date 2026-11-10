<script lang="ts">
	import { ApiError, setMyName, setPublicName } from '#lib/api.ts';
	import { CREDIT_ROLES } from '#lib/labels.ts';
	import RoleSummary from '#lib/RoleSummary.svelte';
	import { getSession } from '#lib/session.ts';
	import { settings } from '#lib/settings.svelte.ts';
	import Switch from '#lib/Switch.svelte';

	const { me, update } = getSession();

	let name = $state(me().display_name);
	let busy = $state(false);
	let saved = $state(false);
	let failure = $state<string | null>(null);

	let named = $state(me().public_name !== null);
	let publicName = $state(me().public_name ?? '');
	let creditBusy = $state(false);
	let creditSaved = $state(false);
	let creditFailure = $state<string | null>(null);
	const roleWording = $derived(CREDIT_ROLES[me().public_role]);

	async function saveCredit(event: SubmitEvent) {
		event.preventDefault();
		creditBusy = true;
		creditSaved = false;
		creditFailure = null;
		try {
			const user = await setPublicName(named ? publicName : null);
			update(user);
			named = user.public_name !== null;
			publicName = user.public_name ?? '';
			creditSaved = true;
		} catch (error) {
			creditFailure =
				error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.';
		} finally {
			creditBusy = false;
		}
	}

	async function save(event: SubmitEvent) {
		event.preventDefault();
		busy = true;
		saved = false;
		failure = null;
		try {
			const user = await setMyName(name);
			update(user);
			name = user.display_name;
			saved = true;
		} catch (error) {
			failure =
				error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.';
		} finally {
			busy = false;
		}
	}

	/** What each Help control last said: "Saved", or why it couldn't save. */
	let helpStatus = $state<Record<string, string>>({});

	async function saveHelp(key: string, change: Parameters<typeof settings.change>[0], done = 'Saved.') {
		helpStatus = { ...helpStatus, [key]: '' };
		try {
			await settings.change(change);
			helpStatus = { ...helpStatus, [key]: done };
		} catch (error) {
			helpStatus = {
				...helpStatus,
				[key]: error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.'
			};
		}
	}
</script>

<svelte:head>
	<title>Settings · Kotoba Table review</title>
</svelte:head>

<h1 class="page-title">Settings</h1>

<h2 class="section-title" id="profile-heading">Profile</h2>

<section class="card" aria-labelledby="name-heading">
	<h3 id="name-heading">Your name</h3>
	<p class="hint">This is how the other reviewers see you on this site.</p>
	<form onsubmit={save}>
		<label>
			<span>Name</span>
			<input
				type="text"
				bind:value={name}
				oninput={() => (saved = false)}
				required
				maxlength="40"
				autocomplete="nickname"
			/>
		</label>
		{#if failure}
			<p role="alert">{failure}</p>
		{:else if saved}
			<p role="status">Saved.</p>
		{/if}
		<button class="primary" type="submit" disabled={busy}>Save name</button>
	</form>
	<p class="email">Signed in as {me().email}</p>
</section>

<section class="card" aria-labelledby="credit-heading">
	<h3 id="credit-heading">Name on published credits</h3>
	<p class="hint">
		When Martin publishes work you reviewed, the app's data and its public history on GitHub credit you this way.
	</p>
	<form onsubmit={saveCredit}>
		<fieldset>
			<legend class="visually-hidden">Credit</legend>
			<label class="choice">
				<input type="radio" name="credit" bind:group={named} value={false} onchange={() => (creditSaved = false)} />
				<span>Stay anonymous (credited as {roleWording})</span>
			</label>
			<label class="choice">
				<input type="radio" name="credit" bind:group={named} value={true} onchange={() => (creditSaved = false)} />
				<span>Use a name</span>
			</label>
		</fieldset>
		{#if named}
			<label>
				<span>Public name</span>
				<input
					type="text"
					bind:value={publicName}
					oninput={() => (creditSaved = false)}
					required
					maxlength="40"
				/>
			</label>
		{/if}
		{#if creditFailure}
			<p role="alert">{creditFailure}</p>
		{:else if creditSaved}
			<p role="status">Saved.</p>
		{/if}
		<button class="primary" type="submit" disabled={creditBusy}>Save credit</button>
	</form>
</section>

<section class="card" aria-labelledby="role-heading">
	<h3 id="role-heading">Your role</h3>
	<RoleSummary role={me().role} />
</section>

<h2 class="section-title" id="help-heading">Help</h2>
<section class="card help" aria-labelledby="help-heading">
	<div class="row">
		<button type="button" onclick={() => saveHelp('tour', { tour: 'reset' }, 'The tour starts next time you open Home.')}
			>Show the tour again</button
		>
		{#if helpStatus.tour}<p role="status">{helpStatus.tour}</p>{/if}
	</div>
	<div class="row">
		<Switch
			label="Tips on pages"
			checked={settings.value.tips_on}
			onchange={(on) => saveHelp('tips', { tips_on: on })}
		/>
		{#if helpStatus.tips}<p role="status">{helpStatus.tips}</p>{/if}
	</div>
	<div class="row">
		<Switch
			label="Keyboard shortcuts"
			checked={settings.value.shortcuts_on}
			onchange={(on) => saveHelp('shortcuts', { shortcuts_on: on })}
		/>
		{#if helpStatus.shortcuts}<p role="status">{helpStatus.shortcuts}</p>{/if}
	</div>
</section>

<style>
	.card {
		max-width: 28rem;
		padding: 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.card + .card {
		margin-top: 1.25rem;
	}

	.page-title {
		margin: 0 0 1rem;
		font-weight: 500;
	}

	.section-title {
		margin: 2rem 0 0.75rem;
		font-size: 1.35rem;
		font-weight: 500;
	}

	h3 {
		margin-top: 0;
		font-weight: 500;
	}

	.help .row {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem 1rem;
	}

	.help .row + .row {
		margin-top: 0.75rem;
	}

	.help p {
		margin: 0;
		color: var(--muted);
	}

	.hint,
	.email {
		color: var(--muted);
	}

	.email {
		margin-bottom: 0;
		overflow-wrap: anywhere;
	}

	form {
		display: grid;
		gap: 0.9rem;
	}

	label {
		display: grid;
		gap: 0.3rem;
	}

	fieldset {
		display: grid;
		gap: 0.5rem;
		margin: 0;
		padding: 0;
		border: 0;
	}

	.choice {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	form p {
		margin: 0;
	}

	form button {
		justify-self: start;
	}
</style>
