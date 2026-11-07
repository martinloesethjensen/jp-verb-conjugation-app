<script lang="ts">
	// The owner's export desk. Above: counters and grammar points ready for a stamp. Below: accepted work and
	// stamps waiting for `make review-pull`; after its PR merges, tick what it carried and mark it exported.
	import { onMount } from 'svelte';
	import {
		getExport,
		getStampable,
		markExported,
		problem,
		stampEntry,
		withdrawStamp,
		type ExportBatch,
		type ReadyEntry
	} from '#lib/api.ts';
	import ErrorLine from '#lib/ErrorLine.svelte';
	import { CREDIT_ROLES, DATASET_TITLES, groupTitle } from '#lib/labels.ts';
	import { suggestionHref } from '#lib/targets.ts';
	import type { Dataset } from '#lib/api.ts';

	let ready = $state<ReadyEntry[] | null>(null);
	let batch = $state<ExportBatch | null>(null);
	let failure = $state<string | null>(null);
	let actionError = $state<string | null>(null);
	let notice = $state<string | null>(null);
	let busy = $state(false);
	/** Ticked rows, as `s<id>` (suggestions) and `t<id>` (stamps): everything is ticked when it loads. */
	let ticked = $state<Set<string>>(new Set());

	const dataset = (name: string) => DATASET_TITLES[name as Dataset] ?? name;
	const credit = (c: { role: keyof typeof CREDIT_ROLES; name: string | null }) => c.name ?? CREDIT_ROLES[c.role];
	const entryHref = (d: string, id: string) => `/item?${new URLSearchParams({ dataset: d, id })}`;
	const empty = $derived(!!batch && batch.suggestions.length === 0 && batch.stamps.length === 0);

	async function load() {
		const [r, b] = await Promise.all([getStampable(), getExport()]);
		ready = r;
		batch = b;
		ticked = new Set([...b.suggestions.map((s) => `s${s.id}`), ...b.stamps.map((t) => `t${t.id}`)]);
	}

	onMount(() => {
		load().catch((error) => (failure = problem(error)));
	});

	function toggle(key: string) {
		const next = new Set(ticked);
		if (next.has(key)) next.delete(key);
		else next.add(key);
		ticked = next;
	}

	async function act(action: () => Promise<string | null>) {
		busy = true;
		actionError = null;
		notice = null;
		try {
			notice = await action();
			await load();
		} catch (error) {
			actionError = problem(error);
		} finally {
			busy = false;
		}
	}

	const stamp = (e: ReadyEntry) =>
		act(async () => {
			await stampEntry(e.dataset, e.item_id);
			return `Stamped ${e.title}.`;
		});

	const unstamp = (d: string, id: string) =>
		act(async () => {
			await withdrawStamp(d, id);
			return null;
		});

	const mark = () =>
		act(async () => {
			const ids = (prefix: string) =>
				[...ticked].filter((k) => k.startsWith(prefix)).map((k) => Number(k.slice(1)));
			const done = await markExported(ids('s'), ids('t'));
			return `Marked ${done.suggestions} suggestions and ${done.stamps} stamps as exported.`;
		});
</script>

<svelte:head>
	<title>Export · Kotoba Table review</title>
</svelte:head>

<p class="back"><a href="/admin">Back to admin</a></p>
<h1>Export</h1>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if !ready || !batch}
	<p class="quiet">Loading…</p>
{:else}
	<ErrorLine message={actionError} />
	{#if notice}<p class="notice" role="status">{notice}</p>{/if}

	<section aria-labelledby="ready-heading">
		<h2 id="ready-heading">Ready to stamp</h2>
		<p class="hint">
			Counters and grammar points whose every part is approved, with nothing open. A stamp names the most
			senior reviewer who approved it, and the app shows the entry as reviewed after the next export.
		</p>
		{#if ready.length === 0}
			<p class="quiet">Nothing is ready to stamp.</p>
		{:else}
			<ul class="rows">
				{#each ready as e (`${e.dataset}/${e.item_id}`)}
					<li>
						<div>
							<a href={entryHref(e.dataset, e.item_id)} lang="ja">{e.title}</a>
							<span class="kind">{dataset(e.dataset)}</span>
						</div>
						<button type="button" class="primary" disabled={busy} onclick={() => stamp(e)}>Stamp as reviewed</button>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section aria-labelledby="waiting-heading">
		<h2 id="waiting-heading">Waiting for export</h2>
		<p class="hint">
			Run <code>make review-pull</code> to put these in a data branch. After its PR merges, mark what it
			contained.
		</p>
		{#if empty}
			<p class="quiet">Nothing is waiting for export.</p>
		{:else}
			<ul class="rows">
				{#each batch.suggestions as s (`s${s.id}`)}
					<li>
						<label class="tick">
							<input type="checkbox" checked={ticked.has(`s${s.id}`)} onchange={() => toggle(`s${s.id}`)} />
							<span class="visually-hidden">Include {s.item_title}</span>
						</label>
						<div>
							<a href={suggestionHref(s)} lang="ja">{s.item_title}</a>
							<span class="kind">
								{s.action === 'delete' ? 'Remove' : s.action === 'note' ? 'Note' : groupTitle(s)} · {dataset(s.dataset)}
							</span>
							<p class="credit">Credited as {credit(s.credit)}</p>
						</div>
					</li>
				{/each}
				{#each batch.stamps as t (`t${t.id}`)}
					<li>
						<label class="tick">
							<input type="checkbox" checked={ticked.has(`t${t.id}`)} onchange={() => toggle(`t${t.id}`)} />
							<span class="visually-hidden">Include the stamp on {t.item_title}</span>
						</label>
						<div>
							<a href={entryHref(t.dataset, t.item_id)} lang="ja">{t.item_title}</a>
							<span class="kind">Stamp · {dataset(t.dataset)}</span>
							<p class="credit">Credited as {credit({ role: t.by, name: t.name })}</p>
						</div>
						<button type="button" class="link" disabled={busy} onclick={() => unstamp(t.dataset, t.item_id)}>
							Withdraw stamp
						</button>
					</li>
				{/each}
			</ul>
			<button type="button" class="primary" disabled={busy || ticked.size === 0} onclick={mark}>
				Mark ticked as exported
			</button>
		{/if}
	</section>
{/if}

<style>
	h1 {
		margin-top: 0;
		font-size: 1.5rem;
		font-weight: 500;
	}

	section {
		margin-bottom: 2rem;
	}

	.hint,
	.quiet,
	.kind,
	.credit {
		color: var(--muted);
	}

	.rows {
		display: grid;
		gap: 0.5rem;
		margin: 0 0 1rem;
		padding: 0;
		list-style: none;
	}

	.rows li {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem 1rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.rows li > div {
		flex: 1 1 12rem;
		min-width: 0;
	}

	.kind {
		margin-left: 0.5rem;
		font-size: 0.9rem;
	}

	.credit {
		margin: 0.2rem 0 0;
		font-size: 0.9rem;
	}

	.tick {
		display: flex;
	}
</style>
