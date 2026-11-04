<script lang="ts">
	import { ApiError, setMyName } from '#lib/api.ts';
	import { getSession } from '#lib/session.ts';

	const { me, update } = getSession();

	let name = $state(me().display_name);
	let busy = $state(false);
	let saved = $state(false);
	let failure = $state<string | null>(null);

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

<style>
	.card {
		max-width: 28rem;
		padding: 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	h1 {
		margin-top: 0;
		font-size: 1.5rem;
		font-weight: 500;
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

	form p {
		margin: 0;
	}

	form button {
		justify-self: start;
	}
</style>
