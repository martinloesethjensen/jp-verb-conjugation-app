<script lang="ts">
	// The owner's export desk. Above: entries and verb examples ready for a stamp. Below: accepted work and
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
	import { groupReady, idsFromSummary } from '#lib/export.ts';
	import { CREDIT_ROLES, DATASET_TITLES, groupTitle } from '#lib/labels.ts';
	import { suggestionHref } from '#lib/targets.ts';
	import type { Dataset } from '#lib/api.ts';

	let ready = $state<ReadyEntry[] | null>(null);
	let batch = $state<ExportBatch | null>(null);
	let failure = $state<string | null>(null);
	let actionError = $state<string | null>(null);
	let notice = $state<string | null>(null);
	let busy = $state(false);
	/** Ticked rows, as `s<id>` (suggestions) and `t<id>` (stamps). Nothing is ticked until the owner pastes
	 * the PR summary's ids or ticks rows: what the pull skipped, or what came after it, must stay waiting. */
	let ticked = $state<Set<string>>(new Set());
	let pasted = $state('');

	const dataset = (name: string) => DATASET_TITLES[name as Dataset] ?? name;
	const credit = (c: { role: keyof typeof CREDIT_ROLES; name: string | null }) => c.name ?? CREDIT_ROLES[c.role];
	const entryHref = (d: string, id: string) => `/item?${new URLSearchParams({ dataset: d, id })}`;
	const empty = $derived(!!batch && batch.suggestions.length === 0 && batch.stamps.length === 0);

	async function load() {
		const [r, b] = await Promise.all([getStampable(), getExport()]);
		ready = r;
		batch = b;
		ticked = new Set([...ticked].filter((k) => rowKeys(b).has(k)));
	}

	const rowKeys = (b: ExportBatch) =>
		new Set([...b.suggestions.map((s) => `s${s.id}`), ...b.stamps.map((t) => `t${t.id}`)]);

	/** Ticks exactly the ids in a pasted PR summary that are still waiting. */
	function tickFromSummary() {
		if (!batch) return;
		const ids = idsFromSummary(pasted);
		const keys = rowKeys(batch);
		ticked = new Set([...ids.suggestions.map((id) => `s${id}`), ...ids.stamps.map((id) => `t${id}`)].filter((k) => keys.has(k)));
		notice = ticked.size === 0 ? 'No waiting ids found in that text.' : null;
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

	const groups = $derived(ready ? groupReady(ready) : []);

	const stamp = (e: ReadyEntry) =>
		act(async () => {
			await stampEntry(e.dataset, e.item_id, e.kind);
			return `Stamped ${e.title}.`;
		});

	/** Stamps a group's examples one after another, stopping at the first that fails. */
	const stampAll = (examples: ReadyEntry[], title: string) =>
		act(async () => {
			for (const e of examples) await stampEntry(e.dataset, e.item_id, e.kind);
			return `Stamped ${examples.length} examples of ${title}.`;
		});

	const unstamp = (d: string, id: string, kind: string) =>
		act(async () => {
			await withdrawStamp(d, id, kind);
			return null;
		});

	const mark = () =>
		act(async () => {
			const ids = (prefix: string) =>
				[...ticked].filter((k) => k.startsWith(prefix)).map((k) => Number(k.slice(1)));
			const done = await markExported(ids('s'), ids('t'));
			const count = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;
			return `Marked ${count(done.suggestions, 'suggestion')} and ${count(done.stamps, 'stamp')} as exported.`;
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
			Entries and verb example sentences whose every part is approved, with nothing open. A stamp names the
			most senior reviewer involved, and the app shows it as reviewed after the next export. A verb's stamp
			covers its meaning, notes and common phrases; each example sentence is stamped on its own.
		</p>
		{#if ready.length === 0}
			<p class="quiet">Nothing is ready to stamp.</p>
		{:else}
			<ul class="rows">
				{#each groups as g (g.key)}
					<li>
						<div>
							<a href={entryHref(g.key.split('/')[0], g.entry?.item_id ?? g.examples[0].entry_id)} lang="ja">{g.title}</a>
							<span class="kind">{dataset(g.key.split('/')[0])}{g.entry ? '' : ' · examples only'}</span>
						</div>
						{#if g.entry}
							{@const entry = g.entry}
							<button type="button" class="primary" disabled={busy} onclick={() => stamp(entry)}>Stamp as reviewed</button>
						{/if}
						{#if g.examples.length > 0}
							<ul class="examples">
								{#each g.examples as e (e.item_id)}
									<li>
										<span lang="ja">{e.title}</span>
										<button type="button" disabled={busy} onclick={() => stamp(e)}>Stamp example</button>
									</li>
								{/each}
							</ul>
							{#if g.examples.length > 1}
								<button type="button" disabled={busy} onclick={() => stampAll(g.examples, g.title)}>
									Stamp all {g.examples.length} examples
								</button>
							{/if}
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section aria-labelledby="waiting-heading">
		<h2 id="waiting-heading">Waiting for export</h2>
		<p class="hint">
			Run <code>make review-pull</code> to put these in a data branch. After its PR merges, paste the
			summary's last line ("Site suggestion ids: …") to tick exactly what it wrote, then mark those exported.
			Anything it skipped stays here.
		</p>
		{#if empty}
			<p class="quiet">Nothing is waiting for export.</p>
		{:else}
			<form class="paste" onsubmit={(e) => (e.preventDefault(), tickFromSummary())}>
				<label>
					<span>Ids from the PR summary</span>
					<input type="text" bind:value={pasted} placeholder="Site suggestion ids: 12, 13. Stamp ids: none." />
				</label>
				<button type="submit">Tick these</button>
			</form>
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
							<p class="credit">Suggestion {s.id} · credited as {credit(s.credit)}</p>
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
							<a href={entryHref(t.dataset, t.entry_id)} lang="ja">{t.item_title}</a>
							<span class="kind">{t.kind === 'example' ? 'Example stamp' : 'Stamp'} · {dataset(t.dataset)}</span>
							<p class="credit">Stamp {t.id} · credited as {credit({ role: t.by, name: t.name })}</p>
						</div>
						<button type="button" class="link" disabled={busy} onclick={() => unstamp(t.dataset, t.item_id, t.kind)}>
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

	.examples {
		display: grid;
		flex-basis: 100%;
		gap: 0.25rem;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.rows .examples li {
		justify-content: space-between;
		padding: 0.5rem 0.75rem;
		border-style: dashed;
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

	.paste {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		gap: 0.5rem;
		margin-bottom: 1rem;
	}

	.paste label {
		display: grid;
		flex: 1 1 16rem;
		gap: 0.3rem;
	}
</style>
