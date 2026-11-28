<script lang="ts">
	// One of your changes: where it is, what it changes (a red-pen correction when we know the before), its tag.
	import type { Change } from './api.ts';
	import { tagFor, textFields, type ChangeGroup } from './contributions.ts';
	import Japanese from './Japanese.svelte';
	import { fieldLabel, JAPANESE_FIELDS, KINDS } from './labels.ts';
	import RedPen from './RedPen.svelte';
	import { suggestionHref } from './targets.ts';

	let {
		change,
		group,
		readings
	}: { change: Change; group: ChangeGroup; readings: Record<string, string> } = $props();

	const tag = $derived(tagFor(change, group));
	const kind = $derived(KINDS[change.kind] ?? change.kind);
	const lead = $derived(
		change.action === 'add'
			? `New ${kind} on`
			: change.action === 'delete'
				? `Removal of ${kind} on`
				: change.action === 'note'
					? 'Note on'
					: `${kind.charAt(0).toUpperCase()}${kind.slice(1)} on`
	);
	// What the change ends as: the editor's wording when it was edited on accepting.
	const after = $derived(textFields(change.admin_edit ?? change.proposed));
	const names = $derived(Object.keys(after));
	const fieldsLine = $derived(change.action === 'change' ? names.map(fieldLabel).join(', ') : '');
	const before = $derived(change.before && change.action === 'change' ? change.before : null);
	const struck = $derived(
		typeof change.before?.jp === 'string' ? change.before.jp : typeof change.before?.en === 'string' ? change.before.en : null
	);
	const replies = $derived(`${change.replies} ${change.replies === 1 ? 'reply' : 'replies'}`);
</script>

<li class="row">
	<div class="top">
		<p class="where">
			{lead} <Japanese text={change.item_title} {readings} />{#if fieldsLine}
				· {fieldsLine}{/if}
		</p>
		<span class={['tag', tag.tone]}>
			{#if tag.tone === 'live'}<svg viewBox="0 0 12 12" aria-hidden="true" width="12" height="12"
					><path d="M2 6.5 5 9.5 10 3" fill="none" stroke="currentColor" stroke-width="2" /></svg
				>{/if}{tag.text}
		</span>
	</div>

	{#if before}
		<RedPen {before} {after} {names} />
	{:else if change.action === 'delete'}
		<p class="struck">
			{#if struck}<Japanese text={struck} {readings} />{:else}<Japanese text={change.item_title} {readings} />{/if}
		</p>
	{:else if names.length}
		<dl class="plain">
			{#each names as name (name)}
				<dt>{fieldLabel(name)}</dt>
				<dd>
					{#if JAPANESE_FIELDS.has(name)}<Japanese text={after[name]} {readings} extra={change.furigana ?? {}} />{:else}{after[name]}{/if}
				</dd>
			{/each}
		</dl>
	{/if}
	{#if change.comment}<p class="note">{change.comment}</p>{/if}

	{#if group === 'declined' && change.reason}
		<p class="reason"><strong>{change.reason.by_name}:</strong> {change.reason.body}</p>
	{/if}
	{#if group === 'waiting' && change.replies > 0}
		<p class="meta"><a href={suggestionHref(change)}>{replies}</a></p>
	{/if}
</li>

<style>
	.row {
		padding: 1rem 1.25rem;
		border-top: 1px solid var(--rule);
	}

	.top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.where {
		margin: 0 0 0.4rem;
		font-size: 0.85rem;
		color: var(--muted);
		overflow-wrap: anywhere;
	}

	.tag {
		flex: none;
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0 0.6rem;
		border: 1px solid var(--muted);
		border-radius: 999px;
		font-size: 0.8rem;
		font-weight: 700;
		color: var(--muted);
		white-space: nowrap;
	}

	.live {
		border-color: var(--green);
		background: var(--green-soft);
		color: var(--green);
	}

	.next {
		border-color: var(--ink);
		color: var(--ink);
	}

	.plain {
		margin: 0;
	}

	dt {
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--muted);
	}

	dd {
		margin: 0 0 0.5rem;
		overflow-wrap: anywhere;
	}

	.struck {
		margin: 0;
		text-decoration: line-through;
		text-decoration-color: var(--red);
		text-decoration-thickness: 2px;
	}

	.note,
	.reason {
		margin: 0.5rem 0 0;
		padding: 0.6rem 0.85rem;
		background: var(--paper);
		border-radius: var(--radius-input);
		white-space: pre-line;
	}

	.meta {
		margin: 0.25rem 0 0;
	}

	.meta a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
	}
</style>
