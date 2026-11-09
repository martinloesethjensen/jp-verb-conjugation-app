<script lang="ts">
	import { ApiError, setMyName, setPublicName } from '#lib/api.ts';
	import { CREDIT_ROLES } from '#lib/labels.ts';
	import { getSession } from '#lib/session.ts';

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
</script>

<svelte:head>
	<title>Your name · Kotoba Table review</title>
</svelte:head>

<section class="card" aria-labelledby="name-heading">
	<h1 id="name-heading">Your name</h1>
	<p class="hint">This is how Martin and the other reviewers see you on this site.</p>
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
	<h2 id="credit-heading">Name on published credits</h2>
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

	h1,
	h2 {
		margin-top: 0;
		font-weight: 500;
	}

	h2 {
		font-size: 1.35rem;
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
