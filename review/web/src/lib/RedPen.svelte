<script lang="ts">
	// A change as a teacher's red-pen correction: removed text struck through, the replacement written
	// above it. Only the fields that changed are shown.
	import { diffFields, type Piece } from './diff.ts';
	import { fieldLabel, JAPANESE_FIELDS } from './labels.ts';

	let {
		before,
		after,
		names
	}: { before: Record<string, unknown>; after: Record<string, unknown>; names: string[] } = $props();

	const changed = $derived(
		diffFields(before, after, names, (name) => (JAPANESE_FIELDS.has(name) ? 'char' : 'word'))
	);

	/** Pieces with each removal and the addition right after it paired up, so the fix sits above. */
	type Run = { same?: string; removed?: string; added?: string };
	function runs(pieces: Piece[]): Run[] {
		const out: Run[] = [];
		for (const piece of pieces) {
			const last = out.at(-1);
			if (piece.added !== undefined && last?.removed !== undefined && last.added === undefined) {
				last.added = piece.added;
			} else out.push({ ...piece });
		}
		return out;
	}
</script>

<dl class="red-pen">
	{#each changed as field (field.name)}
		<dt>{fieldLabel(field.name)}</dt>
		<dd lang={JAPANESE_FIELDS.has(field.name) ? 'ja' : undefined}>
			{#each runs(field.pieces) as run, i (i)}{#if run.same !== undefined}{run.same}{:else}<span
						class="fix"
						>{#if run.added !== undefined}<ins>{run.added}</ins>{/if}{#if run.removed !== undefined}<del
								>{run.removed}</del
							>{/if}</span
					>{/if}{/each}
		</dd>
	{:else}
		<dd class="quiet">No text changed.</dd>
	{/each}
</dl>

<style>
	.red-pen {
		margin: 0;
	}

	dt {
		font-size: 0.8rem;
		color: var(--muted);
	}

	dd {
		margin: 0 0 0.5rem;
		line-height: 2.6;
		overflow-wrap: anywhere;
	}

	dd:lang(ja) {
		font-size: 1.15rem;
	}

	ins,
	del {
		white-space: pre-wrap;
	}

	/* The correction is written above what it replaces. */
	.fix:has(del) {
		display: inline-flex;
		flex-direction: column;
		vertical-align: bottom;
		line-height: 1.3;
	}

	ins {
		color: var(--red);
		text-decoration: none;
		font-size: 0.9em;
	}

	del {
		text-decoration: line-through;
		text-decoration-color: var(--red);
		text-decoration-thickness: 2px;
	}

	/* Text only added (nothing struck) stays in the line, underlined in red. */
	.fix:not(:has(del)) ins {
		text-decoration: underline;
		text-decoration-color: var(--red);
		text-decoration-thickness: 2px;
		font-size: 1em;
	}

	.quiet {
		color: var(--muted);
	}
</style>
