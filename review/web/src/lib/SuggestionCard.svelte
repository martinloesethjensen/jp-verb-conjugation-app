<script lang="ts">
	// One suggestion: who made it, what it changes (as a red-pen correction), its state, and its thread.
	import type { Snippet } from 'svelte';
	import { problem, type Suggestion } from './api.ts';
	import ErrorLine from './ErrorLine.svelte';
	import PartView from './PartView.svelte';
	import RedPen from './RedPen.svelte';
	import { KINDS } from './labels.ts';

	type Json = { [key: string]: any };

	let {
		suggestion,
		current,
		names,
		onwithdraw,
		oncomment,
		actions,
		readings = {},
		forms = {}
	}: {
		suggestion: Suggestion;
		/** The target as it is now; null when it left the data. */
		current: Json | null;
		/** The fields to compare, in order. */
		names: string[];
		onwithdraw?: () => Promise<void>;
		oncomment?: (text: string) => Promise<void>;
		/** Extra buttons (the owner's decisions). */
		actions?: Snippet;
		/** Furigana and form labels, for previewing an addition. */
		readings?: Record<string, string>;
		forms?: Record<string, string>;
	} = $props();

	const uid = $props.id();
	let reply = $state('');
	let busy = $state(false);
	let failure = $state<string | null>(null);

	const s = $derived(suggestion);
	const HEADINGS: Record<string, string> = {
		change: 'suggests a change',
		delete: 'suggests removing it',
		note: 'left a note for Martin',
		add: 'suggests adding this'
	};
	const heading = $derived(`${s.author_name} ${HEADINGS[s.action] ?? HEADINGS.note}`);
	const adding = $derived(s.action === 'add');
	const extra = (item: Json): Record<string, string> => ({ ...(item.readings ?? {}), ...(s.furigana ?? {}) });
	const fieldNames = $derived(names.length ? names : Object.keys(s.proposed ?? {}));
	const status = $derived(s.status === 'accepted' ? 'Accepted' : s.status === 'declined' ? 'Declined' : null);

	async function run(action: () => Promise<void>) {
		busy = true;
		failure = null;
		try {
			await action();
		} catch (error) {
			failure = problem(error);
		} finally {
			busy = false;
		}
	}

	async function send(event: SubmitEvent) {
		event.preventDefault();
		const text = reply.trim();
		if (!text || !oncomment) return;
		await run(async () => {
			await oncomment(text);
			reply = '';
		});
	}
</script>

<article class={['suggestion', { decided: s.status !== 'open' }]}>
	<header>
		<span class="who">{heading}</span>
		{#if adding}<span class="status new">New</span>{/if}
		{#if status}<span class="status">{status}</span>{/if}
		{#if adding && s.landed}<span class="status">Now in the data</span>{/if}
		{#if s.gone}<span class="flag">No longer in the data</span>
		{:else if s.stale}<span class="flag">Changed since</span>{/if}
	</header>

	{#if adding && s.proposed}
		<div class="added">
			<PartView dataset={s.dataset} kind={s.kind} value={s.proposed} readings={{ ...readings, ...extra(s.proposed) }} {forms} />
		</div>
	{:else if s.action === 'change' && s.proposed}
		<RedPen before={current ?? {}} after={s.proposed} names={fieldNames} />
	{:else if s.action === 'delete'}
		<p class="remove">Remove this {KINDS[s.kind] ?? s.kind}</p>
	{/if}
	{#if s.admin_edit}
		<p class="quiet">Martin's version:</p>
		{#if adding}
			<RedPen before={s.proposed ?? {}} after={s.admin_edit} names={Object.keys(s.admin_edit).filter((k) => typeof s.admin_edit?.[k] === 'string')} />
		{:else}
			<RedPen before={current ?? {}} after={s.admin_edit} names={fieldNames} />
		{/if}
	{/if}
	{#if s.furigana && Object.keys(s.furigana).length}
		<ul class="readings">
			{#each Object.entries(s.furigana) as [kanji, reading] (kanji)}
				<li><span lang="ja">{kanji}</span> read as <span lang="ja">{reading}</span></li>
			{/each}
		</ul>
	{/if}
	{#if s.dropped_blanks}
		<p class="quiet">
			{s.dropped_blanks} particle {s.dropped_blanks === 1 ? 'blank' : 'blanks'} dropped; mark them again at export
		</p>
	{/if}
	{#if s.comment}<p class="note">{s.comment}</p>{/if}

	{#if s.comments.length}
		<ol class="thread">
			{#each s.comments as c, i (i)}
				<li><span class="author">{c.author_name}</span> {c.body}</li>
			{/each}
		</ol>
	{/if}

	{#if oncomment || actions || (s.mine && s.status === 'open' && onwithdraw)}
		<div class="footer">
			{#if oncomment}
				<form class="reply" onsubmit={send}>
					<label class="visually-hidden" for="{uid}-reply">Reply</label>
					<textarea id="{uid}-reply" rows="1" maxlength="2000" placeholder="Reply" bind:value={reply}></textarea>
					<button class="small" disabled={busy || !reply.trim()}>Reply</button>
				</form>
			{/if}
			<div class="actions">
				{@render actions?.()}
				{#if s.mine && s.status === 'open' && onwithdraw}
					<button type="button" class="link" disabled={busy} onclick={() => run(onwithdraw)}>Withdraw</button>
				{/if}
			</div>
		</div>
	{/if}
	<ErrorLine message={failure} />
</article>

<style>
	.suggestion {
		margin-top: 0.6rem;
		padding: 0.6rem 0.85rem;
		border-left: 3px solid var(--red);
		background: var(--red-soft);
		border-radius: 0 var(--radius) var(--radius) 0;
	}

	.decided {
		border-left-color: var(--rule);
		background: var(--paper);
		color: var(--muted);
	}

	header {
		display: flex;
		flex-wrap: wrap;
		gap: 0.25rem 0.75rem;
		align-items: baseline;
		margin-bottom: 0.35rem;
	}

	.who {
		font-weight: 500;
	}

	.status,
	.flag {
		font-size: 0.8rem;
		padding: 0 0.45rem;
		border: 1px solid currentColor;
		border-radius: 1rem;
	}

	.flag {
		color: var(--red);
	}

	.new {
		color: var(--green);
	}

	.added {
		margin: 0.25rem 0;
		padding: 0 0.6rem;
		background: var(--card);
		border-left: 2px solid var(--green);
		border-radius: var(--radius);
	}

	.remove {
		margin: 0.25rem 0;
		text-decoration: line-through;
		text-decoration-color: var(--red);
	}

	.note {
		margin: 0.4rem 0;
		padding: 0.4rem 0.6rem;
		background: var(--card);
		border-radius: var(--radius);
		white-space: pre-line;
	}

	.quiet {
		margin: 0.3rem 0;
		font-size: 0.85rem;
		color: var(--muted);
	}

	.readings {
		margin: 0.3rem 0;
		padding-left: 1.1rem;
	}

	.thread {
		margin: 0.5rem 0 0;
		padding: 0;
		list-style: none;
		font-size: 0.92rem;
	}

	.thread li + li {
		margin-top: 0.25rem;
	}

	.author {
		font-weight: 500;
	}

	.footer {
		display: grid;
		gap: 0.4rem;
		margin-top: 0.5rem;
	}

	.reply {
		display: flex;
		gap: 0.5rem;
		align-items: flex-start;
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
		align-items: center;
	}

	.actions:empty {
		display: none;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
	}
</style>
